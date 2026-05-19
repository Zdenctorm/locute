import AVFoundation
import Cocoa
import Combine
import Sparkle
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var stateMachine: AppStateMachine!
    private var statusBarController: StatusBarController!
    private var hotkeyManager: HotkeyManager!
    private var audioRecorder: AudioRecorder!
    private var transcriptionEngine: TranscriptionEngine!
    private var recordingOverlay: RecordingOverlayController!
    private var permissionsWindowController: PermissionsWindowController?
    private var launchWindowController: LaunchWindowController?
    private var updaterController: SPUStandardUpdaterController!
    private var lastTranscriptionText: String?
    private var transcriptionHistory: [TranscriptionHistoryEntry] = []
    private let maxTranscriptionHistoryCount = 40
    private var backgroundInjectTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var microphoneArmTask: Task<Void, Never>?
    private var stateCancellable: AnyCancellable?
    private var optionHeld = false
    private var transcriptionTestMode = false
    /// Frontmost app at the moment user STARTED dictation. Captured here (not at end) because by
    /// the time the user releases Option, focus may have shifted (e.g. recording overlay, status
    /// menu, or window activation). At keyDown the user is still in their target app.
    private var pendingDictationTarget: NSRunningApplication?

    private let logger = Logger(subsystem: "com.example.dictator", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticsLogger.log("App launched. Bundle path: \(Bundle.main.bundleURL.path)")
        DiagnosticsLogger.logStartupContext()

        stateMachine = AppStateMachine()
        audioRecorder = AudioRecorder()
        transcriptionEngine = TranscriptionEngine()
        hotkeyManager = HotkeyManager()
        hotkeyManager.preference = HotkeyPreference.current
        NotificationCenter.default.addObserver(
            forName: .dictatorHotkeyPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotkeyManager.preference = HotkeyPreference.current
            DiagnosticsLogger.log("HotkeyManager updated to preference \(HotkeyPreference.current.rawValue)")
        }
        NotificationCenter.default.addObserver(
            forName: .dictatorVocabularyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.transcriptionEngine.reloadVocabulary()
            }
        }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        recordingOverlay = RecordingOverlayController()
        statusBarController = StatusBarController(
            stateMachine: stateMachine,
            updaterController: updaterController
        )
        launchWindowController = LaunchWindowController(stateMachine: stateMachine)

        wireHotkeys()
        observeAppState()

        statusBarController.onQuit = { NSApp.terminate(nil) }
        statusBarController.onOpenSetup = { [weak self] in self?.showCurrentSetupWindow() }
        statusBarController.onOpenDiagnostics = { DiagnosticsLogger.openLogDirectory() }
        statusBarController.onToggleDictation = { [weak self] in self?.toggleMenuDictation() }
        statusBarController.onTestTranscription = { [weak self] in self?.toggleTranscriptionTest() }
        statusBarController.onShowLastTranscription = { [weak self] in self?.showLastTranscription() }
        launchWindowController?.onRetry = { [weak self] in self?.startStartupTask() }
        launchWindowController?.onRetryInsert = { [weak self] text in
            self?.retryInsert(text: text)
        }

        startStartupTask()
    }

    func applicationWillTerminate(_ notification: Notification) {
        startupTask?.cancel()
        Task { await audioRecorder.cancelRecording() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if stateMachine.state == .permissionsNeeded {
            showCurrentSetupWindow()
        } else {
            showLaunchWindow()
        }
        return true
    }

    private func wireHotkeys() {
        hotkeyManager.onModifierEvent = { [weak self] key, down in
            self?.handleModifierEvent(key: key, down: down)
        }
        hotkeyManager.onKeyDown = { [weak self] in self?.beginDictation(trigger: "hotkey") }
        hotkeyManager.onKeyUp = { [weak self] in self?.endDictation(trigger: "hotkey") }
    }

    private func observeAppState() {
        stateCancellable = stateMachine.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.recordingOverlay.sync(appState: state, rightOptionHeld: self.optionHeld)
                self.statusBarController.refreshDictationMenuItems()
            }
    }

    private func handleModifierEvent(key: HotkeyKey, down: Bool) {
        permissionsWindowController?.reportKeyEvent(key: key, isDown: down)

        switch key {
        case .option, .leftOption:
            optionHeld = down
            if down {
                if stateMachine.isReady {
                    recordingOverlay.show(.keyHeld)
                } else {
                    recordingOverlay.show(busyOverlayMode())
                }
            } else {
                recordingOverlay.sync(appState: stateMachine.state, rightOptionHeld: false)
            }
        }
    }

    private func busyOverlayMode() -> RecordingOverlayMode {
        switch stateMachine.state {
        case .injecting:
            return .busy("Počkejte — ještě vkládám text")
        case .transcribing:
            return .busy("Počkejte — přepisuji")
        case .modelDownloading, .modelLoading, .launching:
            return .busy("Počkejte — připravuji model")
        case .permissionsNeeded:
            return .busy("Nejdřív dokončete nastavení oprávnění")
        case .error:
            return .busy("Dictator vyžaduje pozornost")
        default:
            return .busy("Počkejte — ještě nejsem připravený")
        }
    }

    private func toggleMenuDictation() {
        transcriptionTestMode = false
        if stateMachine.isRecording {
            endDictation(trigger: "menu")
        } else {
            beginDictation(trigger: "menu")
        }
    }

    private func toggleTranscriptionTest() {
        if stateMachine.isRecording && transcriptionTestMode {
            endDictation(trigger: "test")
            return
        }

        guard stateMachine.isReady else {
            statusBarController.showTransientStatus(busyStatusMessage(), duration: 2)
            return
        }

        transcriptionTestMode = true
        beginDictation(trigger: "test")
        statusBarController.showTransientStatus("Test: mluvte a znovu klikněte na „Ověřit přepis“", duration: 4)
    }

    private func showLaunchWindow() {
        AppWindowPresenter.present(launchWindowController?.window)
    }

    private func startStartupTask() {
        startupTask?.cancel()
        DiagnosticsLogger.log("Startup task scheduled")
        startupTask = Task { [weak self] in
            await self?.startup()
        }
    }

    private func startup() async {
        stateMachine.transition(to: .launching)
        DiagnosticsLogger.log("Startup started")

        let permissions = PermissionsWindowController.currentSnapshot
        DiagnosticsLogger.log("Permissions snapshot. microphone=\(permissions.microphone.label), accessibility=\(permissions.accessibility.label)")
        guard permissions.allGranted else {
            stateMachine.transition(to: .permissionsNeeded)
            DiagnosticsLogger.log("Startup paused: permissions needed")
            installHotkeyIfPossible()
            showPermissionsWindow()
            return
        }

        permissionsWindowController?.close()
        permissionsWindowController = nil
        showLaunchWindow()

        guard installHotkeyIfPossible() else {
            stateMachine.transition(to: .permissionsNeeded)
            showPermissionsWindow()
            return
        }

        stateMachine.transition(to: .modelDownloading(.empty))
        DiagnosticsLogger.log("Model load started")
        do {
            try await transcriptionEngine.load { [weak self] progress in
                Task { @MainActor in
                    self?.stateMachine.transition(to: .modelDownloading(progress))
                }
            }
        } catch {
            logger.error("Model load failed: \(error.localizedDescription, privacy: .public)")
            DiagnosticsLogger.log("Model load failed: \(error.localizedDescription)")
            stateMachine.transition(to: .error(modelLoadErrorMessage(for: error)))
            return
        }
        DiagnosticsLogger.log("Model load completed")

        stateMachine.transition(to: .modelLoading)
        stateMachine.transition(to: .idle)
        DiagnosticsLogger.log("Startup completed. App is idle.")
    }

    @discardableResult
    private func installHotkeyIfPossible() -> Bool {
        guard hotkeyManager.install() else {
            DiagnosticsLogger.log("Hotkey install failed. Showing permissions setup.")
            return false
        }
        return true
    }

    private func beginDictation(trigger: String) {
        guard stateMachine.isReady else {
            DiagnosticsLogger.log("Dictation start ignored (\(trigger)): not idle (state=\(stateMachine.state.displayText))")
            statusBarController.showTransientStatus(busyStatusMessage(), duration: 2)
            recordingOverlay.show(busyOverlayMode())
            return
        }

        // Capture target NOW: at this moment the user is still in their target app.
        // Capturing at endDictation was unreliable — the recording overlay or status menu
        // could shift focus to Dictator before user released the key.
        pendingDictationTarget = NSWorkspace.shared.frontmostApplication
        DiagnosticsLogger.log("Dictation start (\(trigger)): target captured as \(pendingDictationTarget?.localizedName ?? "?") (\(pendingDictationTarget?.bundleIdentifier ?? "?"))")

        stateMachine.transition(to: .recording)
        DiagnosticsLogger.enterDictationSession(id: UUID())
        recordingOverlay.show(.recording)
        DiagnosticsLogger.log("Dictation start (\(trigger)): arming microphone")

        microphoneArmTask = Task {
            do {
                try await audioRecorder.startRecording()
                DiagnosticsLogger.log("Microphone pipeline started (\(trigger))")
            } catch {
                logger.error("Recording start failed: \(error.localizedDescription, privacy: .public)")
                DiagnosticsLogger.log("Microphone start failed (\(trigger)): \(error.localizedDescription)")
                await MainActor.run {
                    stateMachine.transition(to: .error("Nahrávání se nepodařilo spustit."))
                }
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    transcriptionTestMode = false
                    DiagnosticsLogger.exitDictationSession()
                    stateMachine.transition(to: .idle)
                }
            }
        }
    }

    private func endDictation(trigger: String) {
        guard stateMachine.isRecording else {
            DiagnosticsLogger.log("Dictation end ignored (\(trigger)): not recording (state=\(stateMachine.state.displayText))")
            return
        }

        // Use target captured at beginDictation. Fallback to current frontmost if missing
        // (e.g. menu-triggered flow that doesn't go through beginDictation properly).
        let targetApp = pendingDictationTarget ?? NSWorkspace.shared.frontmostApplication
        pendingDictationTarget = nil
        DiagnosticsLogger.log("Dictation end (\(trigger)): using target \(targetApp?.localizedName ?? "?") (\(targetApp?.bundleIdentifier ?? "?"))")

        let armTask = microphoneArmTask
        microphoneArmTask = nil

        Task { [weak self, targetApp] in
            await armTask?.value
            guard let self else {
                DiagnosticsLogger.exitDictationSession()
                return
            }
            defer { DiagnosticsLogger.exitDictationSession() }

            DiagnosticsLogger.log("Dictation end (\(trigger)): stopping capture")
            let audioURL = await audioRecorder.stopRecording()
            guard let audioURL else {
                DiagnosticsLogger.log("No audio file (\(trigger)): too short or mic not ready")
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.transcriptionTestMode = false
                    self.stateMachine.transition(to: .idle)
                    self.recordingOverlay.hide()
                    self.statusBarController.showTransientStatus(
                        "Mikrofon nic nezachytil — drž Option déle a mluv hlasitěji",
                        duration: 5
                    )
                }
                if trigger == "test" {
                    self.showTranscriptionTestAlert(
                        text: nil,
                        errorMessage: "Žádný zvuk — drž Option déle (min. cca půl sekundy) a mluv blíž k mikrofonu."
                    )
                }
                return
            }
            defer { try? FileManager.default.removeItem(at: audioURL) }

            await MainActor.run { [weak self] in
                self?.stateMachine.transition(to: .transcribing)
            }

            do {
                let text = try await transcriptionEngine.transcribe(audioURL: audioURL)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

                if trimmed.isEmpty {
                    await handleTranscriptionFailure(
                        trigger: trigger,
                        message: "Nic se nepřepsalo — zkuste mluvit hlasitěji a déle."
                    )
                    return
                }

                DiagnosticsLogger.log("Transcription done (\(trigger)); len=\(trimmed.count)")

                if trigger == "test" {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.transcriptionTestMode = false
                        self.stateMachine.transition(to: .idle)
                    }
                    self.showTranscriptionTestAlert(text: trimmed, errorMessage: nil)
                    return
                }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.publishLastTranscription(trimmed)
                    self.stateMachine.transition(to: .injecting)
                    self.recordingOverlay.hide()
                }

                let injectResult = await pasteWithWatchdog(text: trimmed, into: targetApp, trigger: trigger)
                await MainActor.run { [weak self] in
                    self?.stateMachine.transition(to: .idle)
                    self?.finalizeInjectUI(injectResult, trigger: trigger)
                }
            } catch let error as TranscriptionError {
                let message = transcriptionFailureMessage(for: error)
                DiagnosticsLogger.log("Transcription failed (\(trigger)): \(message)")
                await handleTranscriptionFailure(trigger: trigger, message: message)
            } catch {
                logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                DiagnosticsLogger.log("Transcription failed (\(trigger)): \(error.localizedDescription)")
                await handleTranscriptionFailure(
                    trigger: trigger,
                    message: "Přepis se nepodařil — zkuste to znovu."
                )
            }
        }
    }

    private func handleTranscriptionFailure(trigger: String, message: String) async {
        DiagnosticsLogger.log("Transcription empty (\(trigger))")
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.transcriptionTestMode = false
            self.stateMachine.transition(to: .idle)
            self.recordingOverlay.hide()
            self.statusBarController.showTransientStatus(message, duration: 6)
            self.showLaunchWindow()
        }
        if trigger == "test" {
            await MainActor.run { [weak self] in
                self?.showTranscriptionTestAlert(text: nil, errorMessage: message)
            }
        }
    }

    private func transcriptionFailureMessage(for error: TranscriptionError) -> String {
        switch error {
        case .audioTooQuiet:
            return "Mikrofon skoro nic nezachytil. V Nastavení → Zvuk zkontroluj vstupní zařízení a mluv blíž."
        case .hallucinatedTranscript:
            return "Whisper slyšel jen šum (falešné „titulky“). Mluv hlasitěji — Dictator to záměrně nevloží."
        case .modelNotLoaded:
            return "Model ještě není načtený — počkejte na dokončení stahování."
        }
    }

    private func publishLastTranscription(_ text: String) {
        lastTranscriptionText = text
        transcriptionHistory.insert(
            TranscriptionHistoryEntry(recordedAt: Date(), text: text),
            at: 0
        )
        if transcriptionHistory.count > maxTranscriptionHistoryCount {
            transcriptionHistory.removeSubrange(maxTranscriptionHistoryCount ..< transcriptionHistory.count)
        }
        pushTranscriptionHistoryToPanels()
    }

    private func pushTranscriptionHistoryToPanels() {
        launchWindowController?.setTranscriptionHistory(transcriptionHistory)
    }

    private func showLastTranscription() {
        guard let lastTranscriptionText, !lastTranscriptionText.isEmpty else {
            statusBarController.showTransientStatus("Zatím žádný přepis — nejdřív něco nadiktuj", duration: 3)
            return
        }
        launchWindowController?.setTranscriptionHistory(transcriptionHistory)
        launchWindowController?.focusTranscriptionPanel()
    }

    /// Runs paste pipeline with a watchdog; safe from any executor.
    private func pasteWithWatchdog(text: String, into targetApp: NSRunningApplication?, trigger: String) async -> TextInjectResult {
        let watchdog = DispatchWorkItem { [weak self] in
            DiagnosticsLogger.log("Inject watchdog: background inject exceeded 5s (\(trigger))")
            Task { @MainActor in
                guard let self else { return }
                self.recordingOverlay.hide()
                self.statusBarController.showTransientStatus(
                    "Vložení trvá dlouho — text je v okně Dictatoru",
                    duration: 4
                )
            }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5, execute: watchdog)
        defer { watchdog.cancel() }

        try? await Task.sleep(for: .milliseconds(200))
        return await TextInjector.inject(text: text, into: targetApp)
    }

    @MainActor
    private func finalizeInjectUI(_ injectResult: TextInjectResult, trigger: String) {
        if injectResult.succeeded {
            DiagnosticsLogger.log("Paste: background inject succeeded (\(trigger))")
        } else {
            DiagnosticsLogger.log("Paste: background inject failed (\(trigger))")
            showLastTranscription()
            statusBarController.showTransientStatus(
                "Text je v okně Dictatoru — zkopíruj nebo zkus „Vložit“",
                duration: 5
            )
        }
        DiagnosticsLogger.log("Idle after dictation pipeline (\(trigger))")
    }

    private func startBackgroundInject(text: String, trigger: String) {
        backgroundInjectTask?.cancel()
        backgroundInjectTask = Task { [weak self] in
            guard let self else { return }
            let injectResult = await pasteWithWatchdog(text: text, into: nil, trigger: trigger)
            await MainActor.run {
                self.finalizeInjectUI(injectResult, trigger: trigger)
            }
        }
    }

    private func retryInsert(text: String) {
        startBackgroundInject(text: text, trigger: "manual")
        statusBarController.showTransientStatus("Zkouším vložit text…", duration: 2)
    }

    private func showTranscriptionTestAlert(text: String?, errorMessage: String?) {
        let alert = NSAlert()
        alert.alertStyle = text == nil ? .warning : .informational
        if let text {
            alert.messageText = "Přepis funguje"
            alert.informativeText = text
            alert.addButton(withTitle: "Zkopírovat")
            alert.addButton(withTitle: "Zavřít")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        } else {
            alert.messageText = "Přepis se nepodařil"
            alert.informativeText = errorMessage ?? "Neznámá chyba"
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func busyStatusMessage() -> String {
        switch stateMachine.state {
        case .injecting:
            return "Počkejte — vkládám text"
        case .transcribing:
            return "Počkejte — přepisuji"
        case .modelDownloading, .modelLoading:
            return "Počkejte — připravuji model"
        default:
            return "Počkejte — Dictator není připravený"
        }
    }

    private func showCurrentSetupWindow() {
        showPermissionsWindow()
    }

    private func showPermissionsWindow() {
        permissionsWindowController?.close()
        let controller = PermissionsWindowController()
        controller.onPermissionsGranted = { [weak self] in
            self?.permissionsWindowController = nil
            self?.startStartupTask()
        }
        permissionsWindowController = controller
        AppWindowPresenter.present(controller.window)
    }

    private func modelLoadErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain || error.localizedDescription.localizedCaseInsensitiveContains("offline") {
            return "Model Whisper se nepodařilo stáhnout, protože Mac teď nemá funkční připojení k internetu. Připojte se k internetu a klikněte na „Zkusit znovu“. Diktování zůstává lokální; stahuje se jen model pro první spuštění."
        }
        return "Model Whisper se nepodařilo načíst. Klikněte na „Zkusit znovu“, případně zkontrolujte připojení k internetu."
    }
}
