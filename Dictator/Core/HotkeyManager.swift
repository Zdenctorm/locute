import Cocoa
import CoreGraphics
import os

enum HotkeyKey: Sendable {
    case option
    case leftOption
}

enum HotkeyHealth: Equatable, Sendable {
    case notTrusted
    case tapMissing
    case receivingEvents
    case stale(seconds: TimeInterval)
}

/// Volba klávesy pro diktování. Persistováno v UserDefaults pod `hotkeyChoice`.
enum HotkeyChoice: String, CaseIterable {
    case eitherOption
    case rightOption
    case leftOption
    case rightCommand

    var label: String {
        switch self {
        case .eitherOption: return "Levý nebo pravý Option (⌥)"
        case .rightOption: return "Pravý Option (⌥)"
        case .leftOption: return "Levý Option (⌥)"
        case .rightCommand: return "Pravý Command (⌘)"
        }
    }

    /// Kompaktní inline forma — pro hint věty „Podržte X a diktujte".
    var hintLabel: String {
        switch self {
        case .eitherOption: return "Option (⌥)"
        case .rightOption: return "pravý Option (⌥)"
        case .leftOption: return "levý Option (⌥)"
        case .rightCommand: return "pravý Command (⌘)"
        }
    }
}

extension Notification.Name {
    static let dictatorHotkeyPreferenceChanged = Notification.Name("DictatorHotkeyPreferenceChanged")
}

enum HotkeyPreference {
    private static let storageKey = "hotkeyChoice"

    /// Česká klávesnice: pravý Option je často AltGr — pro globální diktování je spolehlivější pravý Command.
    static var recommendedDefault: HotkeyChoice {
        let czech = Locale.preferredLanguages.contains { $0.hasPrefix("cs") }
            || Locale.current.identifier.hasPrefix("cs")
        return czech ? .rightCommand : .eitherOption
    }

    static var current: HotkeyChoice {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storageKey),
                  let choice = HotkeyChoice(rawValue: raw) else {
                return recommendedDefault
            }
            return choice
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: .dictatorHotkeyPreferenceChanged, object: nil)
        }
    }
}

final class HotkeyManager {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onModifierEvent: ((HotkeyKey, Bool) -> Void)?
    var onWrongModifierHint: ((Bool) -> Void)?
    var activationMode: DictationActivationMode = DictationActivationPreference.current
    /// Aktuální volba uživatele — přepíná, která klávesa spouští diktování.
    var preference: HotkeyChoice = .eitherOption

    private var isOptionDown = false
    private var triggerPhysicallyDown = false
    /// Toggle mode: `onKeyDown` fired but AppDelegate has not yet entered `.recording`.
    private var pendingToggleStart = false
    /// When true, health check / cross-app prep must not rebuild the event tap.
    var suppressTapRebuildDuringSession = false
    fileprivate var eventTap: CFMachPort?

    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?
    /// Čte fyzický stav kláves z HID — funguje i když `flagsChanged` z event tapu v cizí appce nepřijde.
    private var keyStatePoller: Timer?
    private var lastPolledTriggerDown = false
    /// Poslední čas, kdy přišel jakýkoli event z tapu. Slouží k detekci tichého úmrtí tapu
    /// (kdy tap je formálně „enabled", ale macOS mu zastavila doručování crossapp eventů).
    fileprivate var lastEventReceivedAt: Date = .init()
    /// Sleduje, jestli jsme posledně viděli accessibility povolené — jakmile se to změní,
    /// musíme tap zrecyklovat (jinak macOS neuvolní crossapp delivery).
    private var lastAccessibilityTrustedSeen: Bool = false
    /// Zabráníme rekurzivní rekonstrukci tapu z více míst najednou.
    private var isRebuildingTap = false
    /// macOS může krátce hlásit `tapIsEnabled == false` i u živého listen-only tapu; bez cooldownu
    /// health check tap každé 2 s zničí a znovu vytvoří → crossapp Option přestane fungovat.
    private var lastRebuildAt: Date = .distantPast
    private var lastCrossAppPrepAt: Date = .distantPast
    private var pendingUserInputRebuild: DispatchWorkItem?
    private let minRebuildInterval: TimeInterval = 12
    private let crossAppPrepInterval: TimeInterval = 3
    private let healthCheckInterval: TimeInterval = 5
    private let logger = Logger(subsystem: "com.example.dictator", category: "hotkey")

    private static let rightCommandKeyCode: CGKeyCode = 54
    private static let leftOptionKeyCode: CGKeyCode = 58
    private static let rightOptionKeyCode: CGKeyCode = 61

    private struct ModifierSnapshot {
        let keyCode: Int
        let alternateDown: Bool
        let commandDown: Bool
        let numericPad: Bool
        let key54Down: Bool
        let key58Down: Bool
        let key61Down: Bool
    }

    init() {
        // Když se aplikace vrátí do popředí (typicky po grantu Accessibility v System Settings),
        // tap může být formálně živý, ale crossapp delivery zatím nefunguje. Recyklujeme ho.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWorkspaceDidActivateApp),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        healthTimer?.invalidate()
        keyStatePoller?.invalidate()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }

    @discardableResult
    func install() -> Bool {
        DiagnosticsLogger.logStartupContext()

        let trusted = AXIsProcessTrusted()
        lastAccessibilityTrustedSeen = trusted

        // Pokud tap už existuje, ale Accessibility se mezitím změnila (typicky: poprvé povolena),
        // musíme tap zrecyklovat. Pouhé tapEnable nestačí — kernel ho nezpůsobí znova
        // doručovat crossapp eventy.
        if eventTap != nil && !trusted {
            tearDownTap()
            DiagnosticsLogger.log("Hotkey install: Accessibility=false — tap removed")
            return false
        }

        guard trusted else {
            return false
        }

        guard InputMonitoringSettings.isGranted() else {
            DiagnosticsLogger.log("Hotkey install blocked: Input Monitoring not granted")
            return false
        }

        if eventTap == nil {
            guard createTap() else { return false }
        }

        CGEvent.tapEnable(tap: eventTap!, enable: true)
        lastEventReceivedAt = Date()
        DiagnosticsLogger.log("Hotkey event tap enabled (AXTrusted=\(trusted))")

        startHealthCheck()
        if keyStatePoller == nil {
            startKeyStatePoller()
        }
        return true
    }

    /// Po přepnutí do cizí appky obnoví tap; rebuild jen při dlouhém tichu (ne při každém switch).
    func prepareForCrossAppUse() {
        guard AccessibilitySettings.isTrusted() else { return }

        if eventTap == nil {
            _ = install()
            return
        }

        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)

        guard !suppressTapRebuildDuringSession else { return }

        let idle = Date().timeIntervalSince(lastEventReceivedAt)
        guard idle > 45 else { return }

        let now = Date()
        guard now.timeIntervalSince(lastCrossAppPrepAt) >= crossAppPrepInterval else { return }
        lastCrossAppPrepAt = now
        rebuildTap(reason: "cross-app stale \(Int(idle))s", force: false)
    }

    /// Volat těsně před začátkem diktování — opraví tiché úmrtí tapu.
    func ensureReadyForDictation() {
        guard AccessibilitySettings.isTrusted() else { return }
        if eventTap == nil {
            _ = install()
            return
        }
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)

        let idle = Date().timeIntervalSince(lastEventReceivedAt)
        if idle > 25 {
            rebuildTap(reason: "pre-dictation idle \(Int(idle))s", force: true)
        }
        lastEventReceivedAt = Date()
    }

    func markDictationSessionActive(_ active: Bool) {
        suppressTapRebuildDuringSession = active
        if active {
            lastEventReceivedAt = Date()
        }
    }

    /// Volá AppDelegate když `beginDictation` neproběhne — reset push i toggle stavu.
    func resetAfterFailedStart() {
        pendingToggleStart = false
        isOptionDown = false
        triggerPhysicallyDown = false
        onModifierEvent?(.option, false)
    }

    /// Ukončení diktování z menu / Esc — bez simulovaného `onKeyUp`.
    func syncToggleStateAfterExternalStop() {
        guard activationMode == .toggle else { return }
        pendingToggleStart = false
        isOptionDown = false
    }

    func reinstallAfterAccessibilityGrant() {
        tearDownTap()
        _ = install()
    }

    func currentHealth() -> HotkeyHealth {
        guard AccessibilitySettings.isTrusted() else { return .notTrusted }
        guard InputMonitoringSettings.isGranted() else { return .notTrusted }
        guard eventTap != nil, keyStatePoller != nil else { return .tapMissing }
        if lastPolledTriggerDown || Date().timeIntervalSince(lastEventReceivedAt) <= 8 {
            return .receivingEvents
        }
        let idle = Date().timeIntervalSince(lastEventReceivedAt)
        return .stale(seconds: idle)
    }

    /// AppDelegate volá po úspěšném `transition(.recording)` v toggle režimu.
    func confirmDictationStarted() {
        pendingToggleStart = false
        if activationMode == .toggle, !isOptionDown {
            isOptionDown = true
        }
    }

    /// AppDelegate volá když `beginDictation` neproběhne (busy, permissions…).
    func abortToggleStartIfNeeded() {
        guard activationMode == .toggle, pendingToggleStart else { return }
        pendingToggleStart = false
        onModifierEvent?(.option, false)
    }

    /// Vytvoří nový event tap a zaregistruje jeho run-loop source. Voláme i pro rebuild.
    @discardableResult
    private func createTap() -> Bool {
        // Vyčistit starý tap (pokud existuje) — bez toho se nedá znova alokovat na stejný eventy.
        tearDownTap()

        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        let locations: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]
        var tap: CFMachPort?
        for location in locations {
            tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: eventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
            if tap != nil {
                DiagnosticsLogger.log("Hotkey event tap created at \(location == .cghidEventTap ? "HID" : "session")")
                break
            }
        }
        guard let tap else {
            logger.error("Unable to install event tap")
            DiagnosticsLogger.log(
                "Hotkey event tap install failed (AX=\(AXIsProcessTrusted()), ListenEvent=\(InputMonitoringSettings.isGranted()))"
            )
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        startKeyStatePoller()
        DiagnosticsLogger.log("Hotkey event tap created (listenOnly, single ingress)")
        return true
    }

    private func tearDownTap() {
        keyStatePoller?.invalidate()
        keyStatePoller = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
    }

    /// Rebuild tapu — nutné, když:
    /// 1. Accessibility se právě přepnula na true (poprvé grantována nebo re-grantována po rebuilu binárky)
    /// 2. Tap odmítl události po `tapDisabledByUserInput` a re-enable nepomohl
    /// 3. Dlouho nepřišel žádný event, ačkoli uživatel typuje (silent death)
    fileprivate func rebuildTap(reason: String, force: Bool = false) {
        guard !isRebuildingTap else { return }

        let now = Date()
        if !force, now.timeIntervalSince(lastRebuildAt) < minRebuildInterval {
            DiagnosticsLogger.log("Hotkey tap rebuild skipped (cooldown): \(reason)")
            return
        }

        isRebuildingTap = true
        defer { isRebuildingTap = false }

        lastRebuildAt = now
        DiagnosticsLogger.log("Hotkey tap rebuild: \(reason)")
        let trusted = AXIsProcessTrusted()
        lastAccessibilityTrustedSeen = trusted

        guard trusted else {
            DiagnosticsLogger.log("Hotkey tap rebuild skipped — AXTrusted=false")
            return
        }

        guard createTap(), let tap = eventTap else {
            DiagnosticsLogger.log("Hotkey tap rebuild failed to create new tap")
            return
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        lastEventReceivedAt = Date()
        DiagnosticsLogger.log("Hotkey tap rebuilt and enabled")
    }

    @objc private func handleAppDidBecomeActive() {
        // Když přepneme Dictator do popředí, je velká šance že jsme se vrátili z System Settings
        // po grantu Accessibility, nebo že macOS přerušilo crossapp delivery. Recyklujeme tap.
        ensureTapAliveAfterFocusChange(reason: "app became active")
    }

    @objc private func handleWorkspaceDidActivateApp(_ note: Notification) {
        // Při každé změně frontmost appky překontrolujeme, jestli accessibility status nedrhne
        // s realitou — typicky se po rebuilu binárky XCodeem AXIsProcessTrusted začne vracet
        // jiné výsledky než kernelové ACL.
        ensureTapAliveAfterFocusChange(reason: "workspace app switch")

        // Obnovit tap i po přepnutí do Dictatoru — Option musí fungovat kdykoliv.
        prepareForCrossAppUse()
    }

    private func ensureTapAliveAfterFocusChange(reason: String) {
        let trusted = AXIsProcessTrusted()

        // Změna trustu od posledního pozorování → vždy rebuild.
        if trusted != lastAccessibilityTrustedSeen {
            lastAccessibilityTrustedSeen = trusted
            if trusted {
                rebuildTap(reason: "AXTrusted flipped to true (\(reason))", force: true)
            }
            return
        }

        guard trusted else { return }
        guard let tap = eventTap else {
            rebuildTap(reason: "no tap exists (\(reason))", force: true)
            return
        }
        // Jen re-enable — `tapIsEnabled` není spolehlivý signál pro rebuild (viz health check).
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    fileprivate func scheduleRebuildAfterUserInput() {
        pendingUserInputRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildTap(reason: "tapDisabledByUserInput", force: true)
        }
        pendingUserInputRebuild = work
        // Krátká prodleva: necháme macOS dokončit flagsChanged z cizí appky (Cursor, terminál).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func startHealthCheck() {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: healthCheckInterval, repeats: true) { [weak self] _ in
            self?.performHealthCheck()
        }
    }

    private func performHealthCheck() {
        let trusted = AXIsProcessTrusted()

        // Flip detekce — typicky po grantu permission nebo po výměně binárky.
        if trusted != lastAccessibilityTrustedSeen {
            lastAccessibilityTrustedSeen = trusted
            if trusted {
                rebuildTap(reason: "AXTrusted flipped to true (health check)", force: true)
                return
            }
        }

        guard trusted, let eventTap else { return }
        guard !suppressTapRebuildDuringSession else { return }

        // `tapIsEnabled` u listen-only tapu často lže; rebuildovat jen při callbacku nebo dlouhém tichu.
        if !CGEvent.tapIsEnabled(tap: eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }

        // Tap formálně živý, ale dlouho neviděl žádný event. Když uživatel pracuje ve foreground
        // appce a my nedostáváme nic přes 30s, je velmi pravděpodobné, že macOS uspala crossapp
        // delivery a tap je třeba zrecyklovat. (V klidu žádné modifier eventy taky nejsou, takže
        // 30s je dostatečně defenzivní hranice — typický uživatel za 30s aspoň jednou hne Shiftem
        // nebo Optionem.)
        // Tohle není silver bullet, ale chrání proti tichému úmrtí tapu.
        let idle = Date().timeIntervalSince(lastEventReceivedAt)
        if idle > 60 {
            rebuildTap(reason: "no events received for \(Int(idle))s (health check)")
        } else {
            // Defenzivně re-enable i u živého tapu — kompatibilita se starším chováním.
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    fileprivate func noteEventReceived() {
        lastEventReceivedAt = Date()
    }

    fileprivate func scheduleFlagsHandling(event: CGEvent) {
        let snap = snapshotFromEvent(event)
        DispatchQueue.main.async { [weak self] in
            self?.applyModifierSnapshotOnMainQueue(snap)
        }
    }

    private func snapshotFromEvent(_ event: CGEvent) -> ModifierSnapshot {
        let key58 = CGEventSource.keyState(.hidSystemState, key: Self.leftOptionKeyCode)
        let key61 = CGEventSource.keyState(.hidSystemState, key: Self.rightOptionKeyCode)
        let key54 = CGEventSource.keyState(.hidSystemState, key: Self.rightCommandKeyCode)
        return ModifierSnapshot(
            keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
            alternateDown: event.flags.contains(.maskAlternate) || key58 || key61,
            commandDown: event.flags.contains(.maskCommand) || key54,
            numericPad: event.flags.contains(.maskNumericPad),
            key54Down: key54,
            key58Down: key58,
            key61Down: key61
        )
    }

    private func snapshotFromHIDKeyState() -> ModifierSnapshot {
        let key58 = CGEventSource.keyState(.hidSystemState, key: Self.leftOptionKeyCode)
        let key61 = CGEventSource.keyState(.hidSystemState, key: Self.rightOptionKeyCode)
        let key54 = CGEventSource.keyState(.hidSystemState, key: Self.rightCommandKeyCode)
        let keyCode: Int = {
            if key61 { return Int(Self.rightOptionKeyCode) }
            if key58 { return Int(Self.leftOptionKeyCode) }
            if key54 { return Int(Self.rightCommandKeyCode) }
            return -1
        }()
        return ModifierSnapshot(
            keyCode: keyCode,
            alternateDown: key58 || key61,
            commandDown: key54,
            numericPad: false,
            key54Down: key54,
            key58Down: key58,
            key61Down: key61
        )
    }

    private func startKeyStatePoller() {
        keyStatePoller?.invalidate()
        keyStatePoller = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.pollHIDKeyState()
        }
        DiagnosticsLogger.log("Hotkey HID key-state poller started (30ms)")
    }

    private func pollHIDKeyState() {
        guard AccessibilitySettings.isTrusted(), InputMonitoringSettings.isGranted() else { return }
        let snap = snapshotFromHIDKeyState()
        let logicSnap = HotkeyTriggerLogic.Snapshot(
            keyCode: snap.keyCode,
            alternateDown: snap.alternateDown,
            commandDown: snap.commandDown,
            key54Down: snap.key54Down,
            key58Down: snap.key58Down,
            key61Down: snap.key61Down
        )
        let triggerDown = HotkeyTriggerLogic.isTriggerDown(preference: preference, snap: logicSnap)
        if triggerDown != lastPolledTriggerDown {
            lastPolledTriggerDown = triggerDown
            noteEventReceived()
            applyModifierSnapshotOnMainQueue(snap)
        }
    }

    private func applyModifierSnapshotOnMainQueue(_ snap: ModifierSnapshot) {
        DiagnosticsLogger.logFlagsChanged(
            keycode: snap.keyCode,
            alt: snap.alternateDown,
            numericPad: snap.numericPad,
            key58Down: snap.key58Down,
            key61Down: snap.key61Down
        )

        let logicSnap = HotkeyTriggerLogic.Snapshot(
            keyCode: snap.keyCode,
            alternateDown: snap.alternateDown,
            commandDown: snap.commandDown,
            key54Down: snap.key54Down,
            key58Down: snap.key58Down,
            key61Down: snap.key61Down
        )
        let triggerDown = HotkeyTriggerLogic.isTriggerDown(preference: preference, snap: logicSnap)
        let source: String = {
            switch preference {
            case .eitherOption:
                return snap.key61Down ? "rightOption" : (snap.key58Down ? "leftOption" : "keycode-\(snap.keyCode)")
            case .rightOption: return "rightOption"
            case .leftOption: return "leftOption"
            case .rightCommand: return "rightCommand"
            }
        }()

        let sessionActive = isOptionDown || pendingToggleStart
        onWrongModifierHint?(HotkeyTriggerLogic.wrongModifierActive(
            preference: preference,
            snap: logicSnap,
            sessionActive: sessionActive
        ))

        if activationMode == .toggle {
            if triggerDown && !triggerPhysicallyDown {
                triggerPhysicallyDown = true
                if isOptionDown {
                    isOptionDown = false
                    DiagnosticsLogger.log("Hotkey: toggle stop (preference=\(preference.rawValue))")
                    onModifierEvent?(.option, false)
                    onKeyUp?()
                } else {
                    pendingToggleStart = true
                    DiagnosticsLogger.log("Hotkey: toggle start (\(source), preference=\(preference.rawValue))")
                    onModifierEvent?(.option, true)
                    onKeyDown?()
                }
            } else if !triggerDown && triggerPhysicallyDown {
                triggerPhysicallyDown = false
                if pendingToggleStart, !isOptionDown {
                    pendingToggleStart = false
                    onModifierEvent?(.option, false)
                }
            }
            return
        }

        if triggerDown {
            if !triggerPhysicallyDown {
                triggerPhysicallyDown = true
            }
            if !isOptionDown {
                isOptionDown = true
                DiagnosticsLogger.log("Hotkey: trigger down (\(source), preference=\(preference.rawValue))")
                onModifierEvent?(.option, true)
                onKeyDown?()
            }
        } else {
            if triggerPhysicallyDown {
                triggerPhysicallyDown = false
            }
            if isOptionDown {
                isOptionDown = false
                DiagnosticsLogger.log("Hotkey: trigger up (preference=\(preference.rawValue))")
                onModifierEvent?(.option, false)
                onKeyUp?()
            }
        }
    }

    func cancelToggleSessionIfNeeded() {
        guard activationMode == .toggle, isOptionDown else { return }
        isOptionDown = false
        pendingToggleStart = false
        triggerPhysicallyDown = false
        onModifierEvent?(.option, false)
        onKeyUp?()
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout {
        DiagnosticsLogger.log("Hotkey tap disabled by timeout; re-enabling")
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            // Pokud i po re-enable není živý, zkusíme tvrdší cestu na main queue.
            if !CGEvent.tapIsEnabled(tap: tap) {
                DispatchQueue.main.async { manager.rebuildTap(reason: "tapDisabledByTimeout re-enable failed") }
            }
        }
        return Unmanaged.passUnretained(event)
    }

    if type == .tapDisabledByUserInput {
        // POZOR: tohle je hlavní příčina crossapp výpadku. macOS sem chodí, když dorazí "rušivý"
        // input (typicky stisk modifikátoru z jiného procesu) a tap nestihne potvrdit doručení.
        // Re-enable často nestačí — tap zůstává „enabled" ale crossapp eventy už nedoručuje.
        // Bezpečné řešení: rebuild na main queue.
        DiagnosticsLogger.log("Hotkey tap disabled by user input; scheduling rebuild")
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        DispatchQueue.main.async { manager.scheduleRebuildAfterUserInput() }
        return Unmanaged.passUnretained(event)
    }

    guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

    manager.noteEventReceived()
    manager.scheduleFlagsHandling(event: event)
    return Unmanaged.passUnretained(event)
}
