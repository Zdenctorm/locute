import Cocoa
import Combine
import ServiceManagement
import Sparkle

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    var onQuit: (() -> Void)?
    var onOpenSetup: (() -> Void)?
    var onOpenDiagnostics: (() -> Void)?
    var onToggleDictation: (() -> Void)?
    var onTestTranscription: (() -> Void)?
    var onShowLastTranscription: (() -> Void)?
    var onOpenLearnedTerms: (() -> Void)?
    var onMenuWillOpen: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let stateMachine: AppStateMachine
    private let updaterController: SPUStandardUpdaterController
    private var cancellables = Set<AnyCancellable>()
    private var pulseTimer: Timer?
    private var transientResetTimer: Timer?
    private var baseStatusTitle = "Spouštím"
    private var lastAnnouncedState: DictatorState?

    private let statusMenuItem = NSMenuItem(title: "Spouštím", action: nil, keyEquivalent: "")
    private let hintMenuItem = NSMenuItem(title: "Podrž diktovací klávesu a mluv", action: nil, keyEquivalent: "")
    private let dictationMenuItem = NSMenuItem(title: "Začít diktování (bez klávesy)", action: #selector(toggleDictation), keyEquivalent: "")
    private let testTranscriptionMenuItem = NSMenuItem(title: "Ověřit přepis (ukáže text)", action: #selector(runTranscriptionTest), keyEquivalent: "")
    private let lastTranscriptionMenuItem = NSMenuItem(title: "Poslední přepis…", action: #selector(showLastTranscription), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Spouštět po přihlášení", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let postProcessingItem = NSMenuItem(title: "Oprava přepisu pomocí AI (lokální LLM)", action: #selector(togglePostProcessing), keyEquivalent: "")

    init(stateMachine: AppStateMachine, updaterController: SPUStandardUpdaterController) {
        self.stateMachine = stateMachine
        self.updaterController = updaterController
        super.init()
        setupMenu()
        observeState()
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

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        statusMenuItem.isEnabled = false
        AccessibilitySupport.configure(statusMenuItem, help: "Aktuální stav Dictatoru")
        menu.addItem(statusMenuItem)

        hintMenuItem.isEnabled = false
        menu.addItem(hintMenuItem)

        dictationMenuItem.target = self
        menu.addItem(dictationMenuItem)

        testTranscriptionMenuItem.target = self
        menu.addItem(testTranscriptionMenuItem)

        lastTranscriptionMenuItem.target = self
        menu.addItem(lastTranscriptionMenuItem)
        menu.addItem(.separator())

        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        postProcessingItem.target = self
        menu.addItem(postProcessingItem)

        let learnedItem = NSMenuItem(title: "Co se Dictator naučil…", action: #selector(openLearnedTerms), keyEquivalent: "")
        learnedItem.target = self
        menu.addItem(learnedItem)

        let setupItem = NSMenuItem(title: "Nastavení a oprávnění", action: #selector(openSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)

        let diagnosticsItem = NSMenuItem(title: "Otevřít diagnostické logy", action: #selector(openDiagnostics), keyEquivalent: "")
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)

        let aboutItem = NSMenuItem(title: "O Dictatoru", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let checkForUpdatesItem = NSMenuItem(
            title: "Zkontrolovat aktualizace…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = updaterController
        menu.addItem(checkForUpdatesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Ukončit Dictator", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        if let button = statusItem.button {
            button.setAccessibilityRole(.button)
            button.setAccessibilityTitle("Dictator")
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        onMenuWillOpen?()
        launchAtLoginItem.state = isLaunchAtLoginEnabled ? .on : .off
        postProcessingItem.state = PostProcessingPreference.isEnabled ? .on : .off
        hintMenuItem.title = "Podrž \(HotkeyPreference.current.hintLabel) a mluv"
        refreshDictationMenuItems()
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
            dictationMenuItem.title = "Začít diktování (bez klávesy)"
            dictationMenuItem.isEnabled = true
            AccessibilitySupport.configure(dictationMenuItem, help: nil)
            testTranscriptionMenuItem.title = "Ověřit přepis (ukáže text)"
            testTranscriptionMenuItem.isEnabled = true
            AccessibilitySupport.configure(testTranscriptionMenuItem, help: nil)
        case .modelDownloading, .modelLoading:
            dictationMenuItem.title = "Začít diktování (model se načítá)"
            dictationMenuItem.isEnabled = true
            AccessibilitySupport.configure(
                dictationMenuItem,
                help: "Můžeš začít mluvit hned; přepis doběhne po načtení modelu."
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

    private func update(for state: DictatorState) {
        pulseTimer?.invalidate()
        pulseTimer = nil

        baseStatusTitle = state.displayText
        if transientResetTimer == nil {
            statusMenuItem.title = baseStatusTitle
        }
        hintMenuItem.title = contextualHint(for: state)
        refreshDictationMenuItems()

        guard let button = statusItem.button else { return }

        switch state {
        case .idle:
            setImage("mic", template: true, decorativeDescription: "Mikrofon, připraveno")
            button.toolTip = "Dictator je připravený. Podrž \(HotkeyPreference.current.hintLabel) nebo diktuj z menu."
        case .recording:
            button.toolTip = "Nahrávám. Pusť klávesu nebo ukonči z menu."
            startRecordingPulse()
        case .transcribing:
            setImage("waveform", template: true, decorativeDescription: "Vlna, přepis")
            button.toolTip = "Přepisuji lokálně na tomto Macu."
        case .injecting:
            setImage("keyboard", template: true, decorativeDescription: "Klávesnice, vkládání")
            button.toolTip = "Vkládám text."
        case .modelDownloading:
            setImage("arrow.down.circle", template: true, decorativeDescription: "Stahování modelu")
            button.toolTip = "Stahuji a připravuji model Whisper."
        case .modelLoading:
            setImage("cpu", template: true, decorativeDescription: "Načítání modelu")
            button.toolTip = "Načítám model Whisper."
        case .permissionsNeeded:
            setImage("mic.slash", template: true, decorativeDescription: "Mikrofon vypnutý")
            button.toolTip = "Dictator potřebuje mikrofon a Zpřístupnění."
        case .error(let message):
            setImage("exclamationmark.triangle", template: true, decorativeDescription: "Varování")
            button.toolTip = message
        case .launching:
            setImage("mic", template: true, decorativeDescription: "Spouštění")
            button.toolTip = "Spouštím Dictator."
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

    private func applyStatusBarAccessibility(for state: DictatorState, button: NSStatusBarButton) {
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
                self.statusMenuItem.title = self.baseStatusTitle
            }
        }
    }

    private func contextualHint(for state: DictatorState) -> String {
        switch state {
        case .idle:
            return "Podrž \(HotkeyPreference.current.hintLabel) nebo použij položku „Začít diktování“."
        case .recording:
            return "Nahrávám — pusť klávesu nebo zvol „Ukončit diktování“."
        case .modelDownloading, .modelLoading, .launching:
            return "Po dokončení přípravy modelu půjde diktovat klávesou \(HotkeyPreference.current.hintLabel)."
        case .transcribing:
            return "Přepisuji lokálně — chvíli strpení."
        case .injecting:
            return "Vkládám text — pokud to trvá dlouho, zkontroluj Zpřístupnění a log."
        case .permissionsNeeded:
            return "Doplň oprávnění mikrofon a Zpřístupnění v Nastavení."
        case .error:
            return "Je potřeba zásah — nápověda výše v menu."
        }
    }

    private func setImage(_ symbolName: String, template: Bool, decorativeDescription: String) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: decorativeDescription)
        button.image?.isTemplate = template
        button.title = " Dictator"
    }

    private func startRecordingPulse() {
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

    @objc private func showLastTranscription() {
        onShowLastTranscription?()
    }

    @objc private func openLearnedTerms() {
        onOpenLearnedTerms?()
    }

    @objc private func openSetup() {
        onOpenSetup?()
    }

    @objc private func openDiagnostics() {
        onOpenDiagnostics?()
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Dictator",
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            .credits: NSAttributedString(string: "Soukromé české diktování. Bez telemetrie, analytiky a backendu. Historie přepisů zůstává jen v okně do ukončení aplikace.")
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        onQuit?()
    }
}
