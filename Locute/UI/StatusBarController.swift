import Cocoa
import Combine
import ServiceManagement
import Sparkle

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    var onQuit: (() -> Void)?
    var onOpenPreferences: (() -> Void)?
    var onOpenSetupGuide: (() -> Void)?
    var onOpenDiagnostics: (() -> Void)?
    var onRunAccessibilityAudit: (() -> Void)?
    var onToggleDictation: (() -> Void)?
    var onTestTranscription: (() -> Void)?
    var onShowLastTranscription: (() -> Void)?
    var onOpenLearnedTerms: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onMenuWillOpen: (() -> Void)?
    var onShowTranscriptionPopover: ((NSStatusBarButton) -> Void)?
    var onPasteAgain: (() -> Void)?
    var onCopyLastTranscript: (() -> Void)?
    var lastTranscriptProvider: (() -> TranscriptionHistoryEntry?)?
    var hotkeyHealthProvider: (() -> HotkeyHealth)?

    var statusButton: NSStatusBarButton? { statusItem.button }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let stateMachine: AppStateMachine
    private let postProcessingReadiness: PostProcessingReadiness
    private var readinessCancellable: AnyCancellable?
    private let updaterController: SPUStandardUpdaterController
    private let sparkleUpdatesAvailable: Bool
    private var cancellables = Set<AnyCancellable>()
    private var pulseTimer: Timer?
    private var transientResetTimer: Timer?
    private var baseStatusTitle = "Spouštím"
    private var lastAnnouncedState: LocuteState?

    private let statusMenuItem = NSMenuItem(title: "Spouštím", action: nil, keyEquivalent: "")
    private let hintMenuItem = NSMenuItem(title: "Podrž diktovací klávesu a mluv", action: nil, keyEquivalent: "")
    private let dictationMenuItem = NSMenuItem(title: "Diktovat", action: #selector(toggleDictation), keyEquivalent: "")
    private let testTranscriptionMenuItem = NSMenuItem(title: "Test přepisu", action: #selector(runTranscriptionTest), keyEquivalent: "")
    private let lastTranscriptionMenuItem = NSMenuItem(
        title: "Poslední přepis…",
        action: #selector(showLastTranscriptionFromMenu),
        keyEquivalent: ""
    )
    private let historyMenuItem = NSMenuItem(
        title: "Otevřít Locute…",
        action: #selector(openHistoryFromMenu),
        keyEquivalent: ""
    )
    private let pasteAgainMenuItem = NSMenuItem(
        title: "Vložit znovu",
        action: #selector(pasteAgainFromMenu),
        keyEquivalent: ""
    )
    private let copyLastTranscriptMenuItem = NSMenuItem(
        title: "Zkopírovat poslední přepis",
        action: #selector(copyLastTranscriptFromMenu),
        keyEquivalent: ""
    )
    private let launchAtLoginItem = NSMenuItem(title: "Spouštět po přihlášení", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let postProcessingItem = NSMenuItem(
        title: "Lepší formátování textu",
        action: #selector(togglePostProcessing),
        keyEquivalent: ""
    )

    init(
        stateMachine: AppStateMachine,
        postProcessingReadiness: PostProcessingReadiness,
        updaterController: SPUStandardUpdaterController,
        sparkleUpdatesAvailable: Bool
    ) {
        self.stateMachine = stateMachine
        self.postProcessingReadiness = postProcessingReadiness
        self.updaterController = updaterController
        self.sparkleUpdatesAvailable = sparkleUpdatesAvailable
        super.init()
        setupMenu()
        observeState()
        observePostProcessingReadiness()
        refreshMenuStatusTitle(for: stateMachine.state)
        update(for: stateMachine.state)
    }

    deinit {
        pulseTimer?.invalidate()
    }

    private func observeState() {
        stateMachine.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.update(for: state) }
            .store(in: &cancellables)
    }

    private func observePostProcessingReadiness() {
        readinessCancellable = postProcessingReadiness.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshMenuStatusTitle(for: self.stateMachine.state)
                self.hintMenuItem.title = self.contextualHint(for: self.stateMachine.state)
            }
    }

    private func refreshMenuStatusTitle(for state: LocuteState) {
        if transientResetTimer != nil { return }
        if state == .idle, let polishLine = postProcessingReadiness.menuStatusLine {
            baseStatusTitle = polishLine
            statusMenuItem.attributedTitle = nil
            statusMenuItem.title = polishLine
        } else if state == .idle {
            baseStatusTitle = state.displayText
            applyStatusMenuTitle(for: state)
        } else {
            baseStatusTitle = state.displayText
            statusMenuItem.attributedTitle = nil
            statusMenuItem.title = baseStatusTitle
        }
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        statusMenuItem.isEnabled = false
        AccessibilitySupport.configure(statusMenuItem, help: "Aktuální stav \(AppBrand.displayName)")
        menu.addItem(statusMenuItem)

        hintMenuItem.isEnabled = false
        menu.addItem(hintMenuItem)

        dictationMenuItem.target = self
        menu.addItem(dictationMenuItem)

        lastTranscriptionMenuItem.target = self
        menu.addItem(lastTranscriptionMenuItem)

        historyMenuItem.target = self
        menu.addItem(historyMenuItem)

        pasteAgainMenuItem.target = self
        pasteAgainMenuItem.isHidden = true
        AccessibilitySupport.configure(
            pasteAgainMenuItem,
            help: "Vloží poslední přepis do aplikace, kde máš kurzor."
        )
        menu.addItem(pasteAgainMenuItem)

        copyLastTranscriptMenuItem.target = self
        copyLastTranscriptMenuItem.isHidden = true
        menu.addItem(copyLastTranscriptMenuItem)

        menu.addItem(.separator())

        let preferencesItem = NSMenuItem(title: "Nastavení…", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(advancedSubmenuItem())
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Ukončit \(AppBrand.displayName)", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        if let button = statusItem.button {
            applyIconOnlyPresentation(to: button)
            button.setAccessibilityRole(.button)
            button.setAccessibilityTitle(AppBrand.displayName)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        onMenuWillOpen?()
        launchAtLoginItem.state = isLaunchAtLoginEnabled ? .on : .off
        postProcessingItem.state = PostProcessingPreference.isEnabled ? .on : .off
        hintMenuItem.title = activationHintLine()
        refreshDictationMenuItems()
        refreshLastTranscriptMenuItems()
    }

    func refreshDictationMenuItems() {
        let state = stateMachine.state
        let disabledHelp = state.dictationMenuDisabledHelp

        switch state {
        case .recording:
            dictationMenuItem.title = "Ukončit diktování a vložit text"
            dictationMenuItem.isEnabled = true
            AccessibilitySupport.configure(dictationMenuItem, help: nil)
            testTranscriptionMenuItem.title = "Ukončit test přepisu"
            testTranscriptionMenuItem.isEnabled = true
            AccessibilitySupport.configure(testTranscriptionMenuItem, help: nil)
        case .idle:
            dictationMenuItem.title = "Diktovat"
            dictationMenuItem.isEnabled = true
            AccessibilitySupport.configure(dictationMenuItem, help: nil)
            testTranscriptionMenuItem.title = "Test přepisu"
            testTranscriptionMenuItem.isEnabled = true
            AccessibilitySupport.configure(testTranscriptionMenuItem, help: nil)
        case .modelDownloading, .modelLoading:
            dictationMenuItem.title = "Diktovat (načítá se model)"
            dictationMenuItem.isEnabled = true
            AccessibilitySupport.configure(
                dictationMenuItem,
                help: "Přepis doběhne po načtení modelu."
            )
            testTranscriptionMenuItem.isEnabled = false
            AccessibilitySupport.configure(testTranscriptionMenuItem, help: disabledHelp)
        case .transcribing, .injecting, .launching:
            dictationMenuItem.isEnabled = false
            testTranscriptionMenuItem.isEnabled = false
            AccessibilitySupport.configure(dictationMenuItem, help: disabledHelp)
            AccessibilitySupport.configure(testTranscriptionMenuItem, help: disabledHelp)
        case .permissionsNeeded, .error:
            dictationMenuItem.isEnabled = false
            testTranscriptionMenuItem.isEnabled = false
            AccessibilitySupport.configure(dictationMenuItem, help: disabledHelp)
            AccessibilitySupport.configure(testTranscriptionMenuItem, help: disabledHelp)
        }
    }

    private func update(for state: LocuteState) {
        pulseTimer?.invalidate()
        pulseTimer = nil

        refreshMenuStatusTitle(for: state)
        hintMenuItem.title = contextualHint(for: state)
        refreshDictationMenuItems()

        guard let button = statusItem.button else { return }

        switch state {
        case .idle:
            setImage("mic", template: true, decorativeDescription: "Mikrofon, připraveno")
            if postProcessingReadiness.isPreparing {
                button.toolTip = "Přepis je připravený. Formátování se načítá — v menu uvidíš průběh."
            } else {
                button.toolTip = "Připraveno. Podrž \(HotkeyPreference.current.hintLabel)."
            }
        case .recording:
            button.toolTip = "Nahrávám. Pusť klávesu nebo ukonči z menu."
            startRecordingPulse()
        case .transcribing:
            setImage("waveform", template: true, decorativeDescription: "Vlna, přepis")
            button.toolTip = "Přepisuji…"
        case .injecting:
            setImage("keyboard", template: true, decorativeDescription: "Klávesnice, vkládání")
            button.toolTip = "Vkládám text."
        case .modelDownloading:
            setImage("arrow.down.circle", template: true, decorativeDescription: "Stahování modelu")
            button.toolTip = "Stahuji model."
        case .modelLoading:
            setImage("cpu", template: true, decorativeDescription: "Načítání modelu")
            button.toolTip = "Načítám model."
        case .permissionsNeeded:
            setImage("mic.slash", template: true, decorativeDescription: "Mikrofon vypnutý")
            button.toolTip = "Chybí oprávnění."
        case .error(let message):
            setImage("exclamationmark.triangle", template: true, decorativeDescription: "Varování")
            button.toolTip = message
        case .launching:
            setImage("mic", template: true, decorativeDescription: "Spouštění")
            button.toolTip = "Spouštím \(AppBrand.displayName)."
        }

        applyStatusBarAccessibility(for: state, button: button)

        if lastAnnouncedState != state {
            lastAnnouncedState = state
            switch state {
            case .recording, .transcribing, .injecting:
                AccessibilitySupport.announce(state.statusBarAccessibilityLabel)
            case .error(let message):
                AccessibilitySupport.announce("Chyba: \(message)")
            default:
                break
            }
        }
    }

    private func applyStatusBarAccessibility(for state: LocuteState, button: NSStatusBarButton) {
        button.setAccessibilityLabel(state.statusBarAccessibilityLabel)
        button.setAccessibilityHelp(state.statusBarAccessibilityHelp)
        button.setAccessibilityRole(.button)
    }

    func showTransientStatus(_ message: String, duration: TimeInterval) {
        statusMenuItem.title = message
        transientResetTimer?.invalidate()
        transientResetTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.transientResetTimer = nil
                self.refreshMenuStatusTitle(for: self.stateMachine.state)
            }
        }
    }

    private func refreshLastTranscriptMenuItems() {
        let entry = lastTranscriptProvider?()
        let hasEntry = entry != nil && !(entry?.text.isEmpty ?? true)
        let canUseLast = hasEntry && stateMachine.state == .idle

        pasteAgainMenuItem.isHidden = !canUseLast
        copyLastTranscriptMenuItem.isHidden = !canUseLast

        if hasEntry, let text = entry?.text {
            let preview = Self.truncatedMenuPreview(text)
            lastTranscriptionMenuItem.title = "Poslední přepis: \(preview)"
            lastTranscriptionMenuItem.isEnabled = true
        } else {
            lastTranscriptionMenuItem.title = "Poslední přepis…"
            lastTranscriptionMenuItem.isEnabled = false
            AccessibilitySupport.configure(
                lastTranscriptionMenuItem,
                help: "Zatím nic."
            )
        }
    }

    private func applyStatusMenuTitle(for state: LocuteState) {
        if case .idle = state {
            let title = NSMutableAttributedString(
                string: "● ",
                attributes: [.foregroundColor: AppTheme.Color.success]
            )
            title.append(NSAttributedString(
                string: state.displayText,
                attributes: [.foregroundColor: NSColor.labelColor]
            ))
            statusMenuItem.attributedTitle = title
        } else {
            statusMenuItem.attributedTitle = nil
            statusMenuItem.title = state.displayText
        }
    }

    private static func truncatedMenuPreview(_ text: String, maxLength: Int = 44) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func contextualHint(for state: LocuteState) -> String {
        if let healthHint = hotkeyHealthHintLine() {
            return healthHint
        }
        switch state {
        case .idle:
            if postProcessingReadiness.isPreparing {
                return "Přepis jde hned. Formátování doběhne v menu."
            }
            if postProcessingReadiness.phase == .unavailable {
                return "Formátování se nepodařilo načíst — platí základní pravidla."
            }
            return "Podrž \(HotkeyPreference.current.hintLabel)."
        case .recording:
            return "Nahrávám — pusť klávesu."
        case .modelDownloading, .modelLoading, .launching:
            return "Načítám model…"
        case .transcribing:
            return "Přepisuji…"
        case .injecting:
            return "Vkládám…"
        case .permissionsNeeded:
            return "Chybí oprávnění — otevři průvodce."
        case .error:
            return "Chyba — viz stav výše."
        }
    }

    private func hotkeyHealthHintLine() -> String? {
        if stateMachine.isRecording { return nil }
        guard let health = hotkeyHealthProvider?() else { return nil }
        switch health {
        case .notTrusted:
            if !InputMonitoringSettings.isGranted() {
                return "Zapni Monitorování vstupu."
            }
            return "Zapni Zpřístupnění."
        case .tapMissing:
            return "Klávesa neaktivní — otevři Nastavení."
        case .stale:
            return "Stiskni \(HotkeyPreference.current.hintLabel) jednou."
        case .receivingEvents:
            return nil
        }
    }

    private func activationHintLine() -> String {
        switch DictationActivationPreference.current {
        case .pushToTalk:
            return "Podrž \(HotkeyPreference.current.hintLabel) a mluv"
        case .toggle:
            return "\(HotkeyPreference.current.hintLabel) = start/stop"
        }
    }

    private func applyIconOnlyPresentation(to button: NSStatusBarButton) {
        button.title = ""
        button.imagePosition = .imageOnly
    }

    private func setImage(_ symbolName: String, template: Bool, decorativeDescription: String) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: decorativeDescription)
        button.image?.isTemplate = template
        applyIconOnlyPresentation(to: button)
    }

    private func advancedSubmenuItem() -> NSMenuItem {
        let advancedMenu = NSMenu(title: "Pokročilé")

        testTranscriptionMenuItem.target = self
        advancedMenu.addItem(testTranscriptionMenuItem)

        launchAtLoginItem.target = self
        advancedMenu.addItem(launchAtLoginItem)

        postProcessingItem.target = self
        advancedMenu.addItem(postProcessingItem)

        let learnedItem = NSMenuItem(
            title: "Naučené termíny…",
            action: #selector(openLearnedTerms),
            keyEquivalent: ""
        )
        learnedItem.target = self
        advancedMenu.addItem(learnedItem)

        let setupGuideItem = NSMenuItem(
            title: "Průvodce nastavením…",
            action: #selector(openSetupGuide),
            keyEquivalent: ""
        )
        setupGuideItem.target = self
        advancedMenu.addItem(setupGuideItem)

        let diagnosticsItem = NSMenuItem(
            title: "Otevřít diagnostické logy",
            action: #selector(openDiagnostics),
            keyEquivalent: ""
        )
        diagnosticsItem.target = self
        advancedMenu.addItem(diagnosticsItem)

        let auditItem = NSMenuItem(
            title: "Analýza zpřístupnění…",
            action: #selector(runAccessibilityAudit),
            keyEquivalent: ""
        )
        auditItem.target = self
        AccessibilitySupport.configure(
            auditItem,
            help: "Uloží zprávu do složky logů."
        )
        advancedMenu.addItem(auditItem)

        let aboutItem = NSMenuItem(title: "O \(AppBrand.displayName)", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        advancedMenu.addItem(aboutItem)

        let checkForUpdatesItem: NSMenuItem
        if sparkleUpdatesAvailable {
            checkForUpdatesItem = NSMenuItem(
                title: "Zkontrolovat aktualizace…",
                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                keyEquivalent: ""
            )
            checkForUpdatesItem.target = updaterController
        } else {
            checkForUpdatesItem = NSMenuItem(
                title: "Aktualizace nejsou dostupné v lokálním buildu",
                action: nil,
                keyEquivalent: ""
            )
            checkForUpdatesItem.isEnabled = false
            AccessibilitySupport.configure(
                checkForUpdatesItem,
                help: "Pro automatické aktualizace je potřeba release podepsaný Developer ID."
            )
        }
        advancedMenu.addItem(checkForUpdatesItem)

        let item = NSMenuItem(title: "Pokročilé", action: nil, keyEquivalent: "")
        item.submenu = advancedMenu
        return item
    }

    private func startRecordingPulse() {
        guard let button = statusItem.button else { return }
        if AccessibilitySupport.shouldReduceMotion {
            setImage("mic.fill", template: false, decorativeDescription: "Mikrofon, nahrávám")
            let recording = AppTheme.Color.recording
            button.image = button.image?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [recording])
            )
            applyStatusBarAccessibility(for: stateMachine.state, button: button)
            return
        }

        var filled = false
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let button = self.statusItem.button else { return }
                filled.toggle()
                let recording = AppTheme.Color.recording
                let image = NSImage(
                    systemSymbolName: filled ? "mic.fill" : "mic",
                    accessibilityDescription: "Mikrofon, nahrávám"
                )?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [recording]))
                button.image = image
                button.image?.isTemplate = false
                self.applyIconOnlyPresentation(to: button)
                self.applyStatusBarAccessibility(for: self.stateMachine.state, button: button)
            }
        }
        pulseTimer?.fire()
    }

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func togglePostProcessing() {
        PostProcessingPreference.isEnabled.toggle()
        postProcessingItem.state = PostProcessingPreference.isEnabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLoginItem.state = isLaunchAtLoginEnabled ? .on : .off
        } catch {
            stateMachine.transition(to: .error("Nepodařilo se změnit spouštění po přihlášení."))
        }
    }

    @objc private func toggleDictation() {
        onToggleDictation?()
    }

    @objc private func runTranscriptionTest() {
        onTestTranscription?()
    }

    /// „Poslední přepis…“ — rychlý náhled; celá historie je v popoveru nebo hlavním okně.
    @objc private func showLastTranscriptionFromMenu() {
        if let button = statusItem.button {
            onShowTranscriptionPopover?(button)
        } else {
            onShowLastTranscription?()
        }
    }

    @objc private func pasteAgainFromMenu() {
        onPasteAgain?()
    }

    @objc private func copyLastTranscriptFromMenu() {
        onCopyLastTranscript?()
    }

    @objc private func openLearnedTerms() {
        onOpenLearnedTerms?()
    }

    @objc private func openHistoryFromMenu() {
        onOpenHistory?()
    }

    @objc private func openPreferences() {
        onOpenPreferences?()
    }

    @objc private func openSetupGuide() {
        onOpenSetupGuide?()
    }

    @objc private func openDiagnostics() {
        onOpenDiagnostics?()
    }

    @objc private func runAccessibilityAudit() {
        onRunAccessibilityAudit?()
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppBrand.displayName,
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            .credits: NSAttributedString(string: "Offline diktování. Bez telemetrie.")
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        onQuit?()
    }
}
