import Cocoa
import CoreGraphics
import os

enum HotkeyKey: Sendable {
    case option
    case leftOption
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

    static var current: HotkeyChoice {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storageKey),
                  let choice = HotkeyChoice(rawValue: raw) else {
                return .eitherOption
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
    /// Aktuální volba uživatele — přepíná, která klávesa spouští diktování.
    var preference: HotkeyChoice = .eitherOption

    private var isOptionDown = false
    fileprivate var eventTap: CFMachPort?

    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?
    /// Poslední čas, kdy přišel jakýkoli event z tapu. Slouží k detekci tichého úmrtí tapu
    /// (kdy tap je formálně „enabled", ale macOS mu zastavila doručování crossapp eventů).
    fileprivate var lastEventReceivedAt: Date = .init()
    /// Sleduje, jestli jsme posledně viděli accessibility povolené — jakmile se to změní,
    /// musíme tap zrecyklovat (jinak macOS neuvolní crossapp delivery).
    private var lastAccessibilityTrustedSeen: Bool = false
    /// Zabráníme rekurzivní rekonstrukci tapu z více míst najednou.
    private var isRebuildingTap = false
    private let logger = Logger(subsystem: "ai.anycoin.dictator", category: "hotkey")

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
            DiagnosticsLogger.log("Hotkey install called but Accessibility=false — keeping existing tap")
        }

        if eventTap == nil {
            guard createTap() else { return false }
        }

        CGEvent.tapEnable(tap: eventTap!, enable: true)
        lastEventReceivedAt = Date()
        DiagnosticsLogger.log("Hotkey event tap enabled (AXTrusted=\(trusted))")

        startHealthCheck()
        return true
    }

    /// Vytvoří nový event tap a zaregistruje jeho run-loop source. Voláme i pro rebuild.
    @discardableResult
    private func createTap() -> Bool {
        // Vyčistit starý tap (pokud existuje) — bez toho se nedá znova alokovat na stejný eventy.
        tearDownTap()

        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Unable to install event tap")
            DiagnosticsLogger.log("Hotkey event tap install failed (AXTrusted=\(AXIsProcessTrusted()))")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        DiagnosticsLogger.log("Hotkey event tap created (listenOnly, single ingress)")
        return true
    }

    private func tearDownTap() {
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
    fileprivate func rebuildTap(reason: String) {
        guard !isRebuildingTap else { return }
        isRebuildingTap = true
        defer { isRebuildingTap = false }

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
    }

    private func ensureTapAliveAfterFocusChange(reason: String) {
        let trusted = AXIsProcessTrusted()

        // Změna trustu od posledního pozorování → vždy rebuild.
        if trusted != lastAccessibilityTrustedSeen {
            lastAccessibilityTrustedSeen = trusted
            if trusted {
                rebuildTap(reason: "AXTrusted flipped to true (\(reason))")
            }
            return
        }

        guard trusted else { return }
        guard let tap = eventTap else {
            rebuildTap(reason: "no tap exists (\(reason))")
            return
        }
        // Pokud tap není enabled, zkusíme nejdřív lehkou cestu. Když to nepomůže, rebuild.
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            if !CGEvent.tapIsEnabled(tap: tap) {
                rebuildTap(reason: "tap not enabled after re-enable (\(reason))")
            }
        }
    }

    private func startHealthCheck() {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.performHealthCheck()
        }
    }

    private func performHealthCheck() {
        let trusted = AXIsProcessTrusted()

        // Flip detekce — typicky po grantu permission nebo po výměně binárky.
        if trusted != lastAccessibilityTrustedSeen {
            lastAccessibilityTrustedSeen = trusted
            if trusted {
                rebuildTap(reason: "AXTrusted flipped to true (health check)")
                return
            }
        }

        guard trusted, let eventTap else { return }

        // Tap formálně neživý → enable, pokud i pak ne, rebuild.
        if !CGEvent.tapIsEnabled(tap: eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            if !CGEvent.tapIsEnabled(tap: eventTap) {
                rebuildTap(reason: "tap not enabled (health check)")
            }
            return
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
        let snap = ModifierSnapshot(
            keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
            alternateDown: event.flags.contains(.maskAlternate),
            commandDown: event.flags.contains(.maskCommand),
            numericPad: event.flags.contains(.maskNumericPad),
            key54Down: CGEventSource.keyState(.hidSystemState, key: Self.rightCommandKeyCode),
            key58Down: CGEventSource.keyState(.hidSystemState, key: Self.leftOptionKeyCode),
            key61Down: CGEventSource.keyState(.hidSystemState, key: Self.rightOptionKeyCode)
        )

        DispatchQueue.main.async { [weak self] in
            self?.applyModifierSnapshotOnMainQueue(snap)
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

        let triggerDown: Bool
        let source: String
        switch preference {
        case .eitherOption:
            triggerDown = snap.alternateDown && (
                snap.key58Down
                    || snap.key61Down
                    || snap.keyCode == Int(Self.leftOptionKeyCode)
                    || snap.keyCode == Int(Self.rightOptionKeyCode)
            )
            source = snap.key61Down ? "rightOption" : (snap.key58Down ? "leftOption" : "keycode-\(snap.keyCode)")
        case .rightOption:
            triggerDown = snap.alternateDown && (snap.key61Down || snap.keyCode == Int(Self.rightOptionKeyCode))
            source = "rightOption"
        case .leftOption:
            triggerDown = snap.alternateDown && (snap.key58Down || snap.keyCode == Int(Self.leftOptionKeyCode))
            source = "leftOption"
        case .rightCommand:
            triggerDown = snap.commandDown && (snap.key54Down || snap.keyCode == Int(Self.rightCommandKeyCode))
            source = "rightCommand"
        }

        if triggerDown {
            if !isOptionDown {
                isOptionDown = true
                DiagnosticsLogger.log("Hotkey: trigger down (\(source), preference=\(preference.rawValue))")
                onModifierEvent?(.option, true)
                onKeyDown?()
            }
        } else if isOptionDown {
            isOptionDown = false
            DiagnosticsLogger.log("Hotkey: trigger up (preference=\(preference.rawValue))")
            onModifierEvent?(.option, false)
            onKeyUp?()
        }
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
        DispatchQueue.main.async { manager.rebuildTap(reason: "tapDisabledByUserInput") }
        return Unmanaged.passUnretained(event)
    }

    guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

    manager.noteEventReceived()
    manager.scheduleFlagsHandling(event: event)
    return Unmanaged.passUnretained(event)
}
