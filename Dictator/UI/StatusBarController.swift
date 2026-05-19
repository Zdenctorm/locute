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

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let stateMachine: AppStateMachine
    private let updaterController: SPUStandardUpdaterController
    private var cancellables = Set<AnyCancellable>()
    private var pulseTimer: Timer?
    private var transientResetTimer: Timer?
    private var baseStatusTitle = "Spouštím"

    private let statusMenuItem = NSMenuItem(title: "Spouštím", action: nil, keyEquivalent: "")
    private let hintMenuItem = NSMenuItem(title: "Podržte diktovací klávesu a mluvte", action: nil, keyEquivalent: "")
    private let dictationMenuItem = NSMenuItem(title: "Začít diktování (bez klávesy)", action: #selector(toggleDictation), keyEquivalent: "")
    private let testTranscriptionMenuItem = NSMenuItem(title: "Ověřit přepis (ukáže text)", action: #selector(runTranscriptionTest), keyEquivalent: "")
    private let lastTranscriptionMenuItem = NSMenuItem(title: "Poslední přepis…", action: #selector(showLastTranscription), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Spouštět po přihlášení", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

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
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem.state = isLaunchAtLoginEnabled ? .on : .off
        hintMenuItem.title = "Podržte \(HotkeyPreference.current.hintLabel) a mluvte"
        refreshDictationMenuItems()
    }

    func refreshDictationMenuItems() {
        switch stateMachine.state {
        case .recording:
            dictationMenuItem.title = "Ukončit diktování a vložit text"
            dictationMenuItem.isEnabled = true
            testTranscriptionMenuItem.title = "Ukončit test přepisu"
            testTranscriptionMenuItem.isEnabled = true
        case .idle:
            dictationMenuItem.title = "Začít diktování (bez klávesy)"
            dictationMenuItem.isEnabled = true
            testTranscriptionMenuItem.title = "Ověřit přepis (ukáže text)"
            testTranscriptionMenuItem.isEnabled = true
        case .transcribing, .injecting, .modelDownloading, .modelLoading, .launching:
            dictationMenuItem.isEnabled = false
            testTranscriptionMenuItem.isEnabled = false
        case .permissionsNeeded, .error:
            dictationMenuItem.isEnabled = false
            testTranscriptionMenuItem.isEnabled = false
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
        guard let button = statusItem.button else { return }

        switch state {
        case .idle:
            setImage("mic", template: true)
            button.toolTip = "Dictator je připravený. Držte Option (⌥) nebo diktujte z menu."
        case .recording:
            button.toolTip = "Nahrávám. Pusťte Option nebo ukončete z menu."
            startRecordingPulse()
        case .transcribing:
            setImage("waveform", template: true)
            button.toolTip = "Přepisuji lokálně na tomto Macu."
        case .injecting:
            setImage("keyboard", template: true)
            button.toolTip = "Vkládám text."
        case .modelDownloading:
            setImage("arrow.down.circle", template: true)
            button.toolTip = "Stahuji a připravuji model Whisper."
        case .modelLoading:
            setImage("cpu", template: true)
            button.toolTip = "Načítám model Whisper."
        case .permissionsNeeded:
            setImage("mic.slash", template: true)
            button.toolTip = "Dictator potřebuje mikrofon a Zpřístupnění."
        case .error(let message):
            setImage("exclamationmark.triangle", template: true)
            button.toolTip = message
        case .launching:
            setImage("mic", template: true)
            button.toolTip = "Spouštím Dictator."
        }
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
            return "Držte \(HotkeyPreference.current.hintLabel) nebo použijte položku „Začít diktování“."
        case .recording:
            return "Nahrávám — pusťte Option nebo zvolte „Ukončit diktování“."
        case .modelDownloading, .modelLoading, .launching:
            return "Po dokončení přípravy modelu půjde diktovat pravým Optionem."
        case .transcribing:
            return "Přepisuji lokálně — chvíli strpení."
        case .injecting:
            return "Vkládám text — pokud to trvá dlouho, zkontrolujte oprávnění Zpřístupnění a log."
        case .permissionsNeeded:
            return "Doplňte oprávnění mikrofon + Zpřístupnění v Nastavení."
        case .error:
            return "Je potřeba zásah — nápověda výše v menu."
        }
    }

    private func setImage(_ symbolName: String, template: Bool) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.image?.isTemplate = template
        button.title = " Dictator"
    }

    private func startRecordingPulse() {
        var filled = false
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                filled.toggle()
                let image = NSImage(systemSymbolName: filled ? "mic.fill" : "mic", accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
                self?.statusItem.button?.image = image
                self?.statusItem.button?.image?.isTemplate = false
            }
        }
        pulseTimer?.fire()
    }

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
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
            stateMachine.transition(to: .error("Unable to update Launch at Login."))
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
