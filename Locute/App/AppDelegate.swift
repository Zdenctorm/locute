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
    private var postProcessingEngine: PostProcessingEngine!
    private var recordingOverlay: RecordingOverlayController!
    private var setupWindowController: SetupWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private var launchWindowController: LaunchWindowController?
    private var historyWindowController: HistoryWindowController?
    private var learnedTermsWindowController: LearnedTermsWindowController?
    private var updaterController: SPUStandardUpdaterController!
    private var lastTranscriptionText: String?
    private var transcriptionHistory: [TranscriptionHistoryEntry] = []
    private let maxTranscriptionHistoryCount = 200
    private var backgroundInjectTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var microphoneArmTask: Task<Void, Never>?
    private var streamingTranscriptionTask: Task<Void, Never>?
    private var stateCancellable: AnyCancellable?
    private var optionHeld = false
    private var transcriptionTestMode = false
    private var escapeMonitor: Any?
    private var keepAliveActivity: NSObjectProtocol?
    private let statusBarPopover = StatusBarPopoverController()
    private var historySaveTimer: Timer?
    private var audioLevelTimer: Timer?
    private var audioCachePurgeTimer: Timer?
    /// Poslední úspěšný přepis pro retry-detektor.
    private var lastDictation: (entry: TranscriptionHistoryEntry, recordedAt: Date)?
    private let retryWindow: TimeInterval = 8.0
    /// Frontmost app at the moment user STARTED dictation. Captured here (not at end) because by
    /// the time the user releases Option, focus may have shifted (e.g. recording overlay, status
    /// menu, or window activation). At keyDown the user is still in their target app.
    private var pendingDictationTarget: NSRunningApplication?
    private let dictationTargetTracker = DictationTargetTracker()

    private let logger = Logger(subsystem: "com.example.locute", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        keepAliveActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "\(AppBrand.displayName) global hotkey monitoring"
        )
        DiagnosticsLogger.log("App launched. Bundle path: \(Bundle.main.bundleURL.path)")
        DiagnosticsLogger.logStartupContext()

        stateMachine = AppStateMachine()
        audioRecorder = AudioRecorder()
        transcriptionEngine = TranscriptionEngine()
        postProcessingEngine = PostProcessingEngine()
        hotkeyManager = HotkeyManager()
        hotkeyManager.preference = HotkeyPreference.current
        hotkeyManager.activationMode = DictationActivationPreference.current
        NotificationCenter.default.addObserver(
            forName: .locuteActivationModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotkeyManager.activationMode = DictationActivationPreference.current
        }
        NotificationCenter.default.addObserver(
            forName: .locuteHotkeyPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotkeyManager.preference = HotkeyPreference.current
            DiagnosticsLogger.log("HotkeyManager updated to preference \(HotkeyPreference.current.rawValue)")
        }
        let sparkleUpdatesAvailable = SparkleUpdateSupport.isAvailable
        DiagnosticsLogger.log("Sparkle updater availability: \(sparkleUpdatesAvailable ? "enabled" : "disabled")")
        NotificationCenter.default.addObserver(
            forName: .locuteTranscriptionModelPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleTranscriptionModelPreferenceChanged()
        }
        NotificationCenter.default.addObserver(
            forName: .locutePostProcessingPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handlePostProcessingPreferenceChanged()
        }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: sparkleUpdatesAvailable,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        recordingOverlay = RecordingOverlayController()
        statusBarController = StatusBarController(
            stateMachine: stateMachine,
            updaterController: updaterController,
            sparkleUpdatesAvailable: sparkleUpdatesAvailable
        )
        statusBarController.hotkeyHealthProvider = { [weak self] in
            self?.hotkeyManager.currentHealth() ?? .tapMissing
        }
        launchWindowController = LaunchWindowController(stateMachine: stateMachine)
        historyWindowController = HistoryWindowController()

        NotificationCenter.default.addObserver(
            forName: .locuteLearnedTermsChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.pushLearningSnapshotToEngine()
            if let canonical = notification.userInfo?["activatedCanonical"] as? String {
                self?.statusBarController.showTransientStatus(
                    "Naučeno: \(canonical)",
                    duration: 4
                )
            }
        }

        wireHotkeys()
        observeAppState()
        dictationTargetTracker.startObserving()

        if PermissionsSnapshotProvider.current.allGranted {
            if !installHotkeyIfPossible() {
                let message: String
                if !InputMonitoringSettings.isGranted() {
                    message = "Chybí Monitorování vstupu."
                } else {
                    message = "Chybí Zpřístupnění."
                }
                statusBarController.showTransientStatus(message, duration: 10)
                showSetupWindow()
            }
        }

        statusBarController.onQuit = { NSApp.terminate(nil) }
        statusBarController.onMenuWillOpen = { [weak self] in
            self?.dictationTargetTracker.snapshotForMenuAction()
        }
        statusBarController.onOpenPreferences = { [weak self] in self?.showPreferencesWindow() }
        statusBarController.onOpenSetupGuide = { [weak self] in self?.showSetupWindow() }
        statusBarController.onOpenDiagnostics = { DiagnosticsLogger.openLogDirectory() }
        statusBarController.onRunAccessibilityAudit = { [weak self] in self?.runAccessibilityAudit() }
        statusBarController.onToggleDictation = { [weak self] in self?.toggleMenuDictation() }
        statusBarController.onTestTranscription = { [weak self] in self?.toggleTranscriptionTest() }
        statusBarController.onShowLastTranscription = { [weak self] in self?.showLastTranscription() }
        statusBarController.onShowTranscriptionPopover = { [weak self] button in
            self?.showTranscriptionPopover(from: button)
        }
        statusBarController.lastTranscriptProvider = { [weak self] in
            self?.transcriptionHistory.first
        }
        statusBarController.onPasteAgain = { [weak self] in
            guard let text = self?.transcriptionHistory.first?.text, !text.isEmpty else { return }
            self?.startBackgroundInject(text: text, trigger: "menu-paste-again")
        }
        statusBarController.onCopyLastTranscript = { [weak self] in
            guard let text = self?.transcriptionHistory.first?.text, !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            self?.statusBarController.showTransientStatus("Zkopírováno", duration: 2)
        }
        statusBarController.onOpenLearnedTerms = { [weak self] in self?.showLearnedTermsWindow() }
        statusBarController.onOpenHistory = { [weak self] in self?.showHistoryWindow() }
        launchWindowController?.onRetry = { [weak self] in self?.startStartupTask() }
        launchWindowController?.onRetryInsert = { [weak self] text in
            self?.retryInsert(text: text)
        }
        launchWindowController?.onOpenHistory = { [weak self] in self?.showHistoryWindow() }
        launchWindowController?.onOpenSetupGuide = { [weak self] in self?.showSetupWindow() }
        historyWindowController?.onRetryInsert = { [weak self] text in
            self?.retryInsert(text: text)
        }

        // Bootstrap learning + persistence + audio housekeeping. Pořadí důležité:
        // 1) Inicializuj LearningEngine (zkonzumuje legacy slovník při prvním běhu).
        // 2) Načti historii z disku, ať uživatel po restartu uvidí předchozí přepisy.
        // 3) Pošli aktivní slovník do TranscriptionEngine ještě před prvním přepisem.
        _ = LearningEngine.shared
        transcriptionHistory = HistoryStore.load()
        pushTranscriptionHistoryToPanels()
        pushLearningSnapshotToEngine()
        AudioCache.purgeStale()
        audioCachePurgeTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            AudioCache.purgeStale()
        }

        installEscapeMonitor()
        WordCorrectionPopoverController.shared.onLearned = { [weak self] _ in
            self?.pushTranscriptionHistoryToPanels()
        }
        startStartupTask()
    }

    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                self?.cancelActiveDictation()
            }
        }
    }

    private func cancelActiveDictation() {
        guard stateMachine.isRecording else { return }
        stopAudioLevelMeterUpdates()
        hotkeyManager.markDictationSessionActive(false)
        hotkeyManager.cancelToggleSessionIfNeeded()
        microphoneArmTask?.cancel()
        microphoneArmTask = nil
        streamingTranscriptionTask?.cancel()
        streamingTranscriptionTask = nil
        transcriptionTestMode = false
        Task {
            await audioRecorder.cancelRecording()
            await transcriptionEngine.endStreaming()
            await MainActor.run { [weak self] in
                guard let self else { return }
                DiagnosticsLogger.exitDictationSession()
                self.stateMachine.transition(to: .idle)
                self.recordingOverlay.showTransientFeedback("Zrušeno", duration: 2)
                SoundFeedbackService.playError()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keepAliveActivity {
            ProcessInfo.processInfo.endActivity(keepAliveActivity)
        }
        startupTask?.cancel()
        historySaveTimer?.invalidate()
        audioLevelTimer?.invalidate()
        audioCachePurgeTimer?.invalidate()
        HistoryStore.save(transcriptionHistory)
        Task { await audioRecorder.cancelRecording() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if stateMachine.state == .permissionsNeeded {
            showSetupWindow()
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
        setupWindowController?.reportKeyEvent(key: key, isDown: down)

        switch key {
        case .option, .leftOption:
            optionHeld = down
            if down {
                if stateMachine.canStartDictation {
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
            return .busy("Počkej — vkládám")
        case .transcribing:
            return .busy("Přepisuji…")
        case .modelDownloading, .modelLoading, .launching:
            return .busy("Načítám model…")
        case .permissionsNeeded:
            return .busy("Dokonči nastavení")
        case .error:
            return .busy("\(AppBrand.displayName) — chyba")
        default:
            return .busy("Počkej…")
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

        guard stateMachine.canStartDictation else {
            statusBarController.showTransientStatus(busyStatusMessage(), duration: 2)
            return
        }

        transcriptionTestMode = true
        beginDictation(trigger: "test")
        statusBarController.showTransientStatus("Test: mluv a klikni znovu.", duration: 4)
    }

    private func showLaunchWindow() {
        AppWindowPresenter.present(launchWindowController?.window)
    }

    private func showHistoryWindow() {
        historyWindowController?.setTranscriptionHistory(transcriptionHistory)
        historyWindowController?.showWindow(nil)
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

        let permissions = PermissionsSnapshotProvider.current
        DiagnosticsLogger.log(
            "Permissions snapshot. microphone=\(permissions.microphone.label), accessibility=\(permissions.accessibility.label), inputMonitoring=\(permissions.inputMonitoring.label)"
        )
        guard permissions.allGranted else {
            stateMachine.transition(to: .permissionsNeeded)
            DiagnosticsLogger.log("Startup paused: permissions needed")
            installHotkeyIfPossible()
            showSetupWindow()
            return
        }

        setupWindowController?.close()
        setupWindowController = nil
        showLaunchWindow()

        guard installHotkeyIfPossible() else {
            stateMachine.transition(to: .permissionsNeeded)
            showSetupWindow()
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
        hotkeyManager.prepareForCrossAppUse()
        DiagnosticsLogger.log("Startup completed. App is idle.")
        launchWindowController?.dismissIfIdle()

        if PostProcessingPreference.isEnabled {
            Task { [weak self] in await self?.startPostProcessingLoad() }
        }
    }

    @discardableResult
    private func installHotkeyIfPossible() -> Bool {
        guard hotkeyManager.install() else {
            DiagnosticsLogger.log("Hotkey install failed. Showing permissions setup.")
            return false
        }
        return true
    }

    private func ensureTranscriptionEngineReady() async throws {
        if await transcriptionEngine.isLoaded { return }

        DiagnosticsLogger.log("Transcription engine not ready — waiting for model load")
        if let startupTask {
            await startupTask.value
        }
        if await transcriptionEngine.isLoaded { return }

        try await transcriptionEngine.load { [weak self] progress in
            Task { @MainActor in
                self?.stateMachine.transition(to: .modelDownloading(progress))
            }
        }
    }

    private func beginDictation(trigger: String) {
        hotkeyManager.ensureReadyForDictation()
        hotkeyManager.prepareForCrossAppUse()
        guard stateMachine.canStartDictation else {
            DiagnosticsLogger.log("Dictation start ignored (\(trigger)): not idle (state=\(stateMachine.state.displayText))")
            hotkeyManager.resetAfterFailedStart()
            statusBarController.showTransientStatus(busyStatusMessage(), duration: 2)
            recordingOverlay.show(busyOverlayMode())
            return
        }

        let menuTriggered = trigger == "menu"
        pendingDictationTarget = dictationTargetTracker.resolveTarget(
            atHotkeyDown: NSWorkspace.shared.frontmostApplication,
            menuTriggered: menuTriggered
        )
        DiagnosticsLogger.log("Dictation start (\(trigger)): target captured as \(pendingDictationTarget?.localizedName ?? "?") (\(pendingDictationTarget?.bundleIdentifier ?? "?"))")

        stateMachine.transition(to: .recording)
        hotkeyManager.markDictationSessionActive(true)
        hotkeyManager.confirmDictationStarted()
        DiagnosticsLogger.enterDictationSession(id: UUID())
        recordingOverlay.show(.recording)
        SoundFeedbackService.playRecordingStart()
        DiagnosticsLogger.log("Dictation start (\(trigger)): arming microphone")

        streamingTranscriptionTask?.cancel()
        streamingTranscriptionTask = nil

        microphoneArmTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await audioRecorder.startRecording()
                DiagnosticsLogger.log("Microphone pipeline started (\(trigger))")
                startAudioLevelMeterUpdates()
                if DictationPreviewPreference.isEnabled {
                    await startStreamingPipelineIfPossible()
                }
            } catch {
                logger.error("Recording start failed: \(error.localizedDescription, privacy: .public)")
                DiagnosticsLogger.log("Microphone start failed (\(trigger)): \(error.localizedDescription)")
                await MainActor.run {
                    self.hotkeyManager.markDictationSessionActive(false)
                    self.hotkeyManager.cancelToggleSessionIfNeeded()
                    self.hotkeyManager.resetAfterFailedStart()
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

        hotkeyManager.markDictationSessionActive(false)
        if trigger != "hotkey" {
            hotkeyManager.syncToggleStateAfterExternalStop()
        }

        // Use target captured at beginDictation. Fallback to current frontmost if missing
        // (e.g. menu-triggered flow that doesn't go through beginDictation properly).
        let targetApp = pendingDictationTarget ?? NSWorkspace.shared.frontmostApplication
        pendingDictationTarget = nil
        DiagnosticsLogger.log("Dictation end (\(trigger)): using target \(targetApp?.localizedName ?? "?") (\(targetApp?.bundleIdentifier ?? "?"))")

        stopAudioLevelMeterUpdates()

        let armTask = microphoneArmTask
        microphoneArmTask = nil
        streamingTranscriptionTask?.cancel()
        streamingTranscriptionTask = nil

        Task { [weak self, targetApp] in
            await armTask?.value
            guard let self else {
                DiagnosticsLogger.exitDictationSession()
                return
            }
            defer { DiagnosticsLogger.exitDictationSession() }

            await audioRecorder.setSamplesUpdateHandler(nil)
            await transcriptionEngine.endStreaming()

            DiagnosticsLogger.log("Dictation end (\(trigger)): stopping capture")
            let capture = await audioRecorder.stopRecording()
            guard let capture else {
                DiagnosticsLogger.log("No audio file (\(trigger)): too short or mic not ready")
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.transcriptionTestMode = false
                    self.stateMachine.transition(to: .idle)
                    self.recordingOverlay.hide()
                    self.statusBarController.showTransientStatus(
                        "Nic nezachytilo — mluv déle a hlasitěji.",
                        duration: 5
                    )
                }
                if trigger == "test" {
                    self.showTranscriptionTestAlert(
                        text: nil,
                        errorMessage: "Nic nezachytilo — mluv déle."
                    )
                }
                return
            }
            await MainActor.run { [weak self] in
                self?.stateMachine.transition(to: .transcribing)
            }

            do {
                try await ensureTranscriptionEngineReady()
                let keyUpAt = Date()
                let result = try await transcriptionEngine.transcribe(
                    audioSamples: capture.audioSamples,
                    peakRMS: capture.peakRMS,
                    audioURL: capture.url
                )
                let raw = result.raw
                let keyUpToDecodeMs = Date().timeIntervalSince(keyUpAt) * 1000
                DiagnosticsLogger.log(
                    "Dictation timing: keyUpToDecodeMs=\(String(format: "%.0f", keyUpToDecodeMs))"
                )

                if raw.rawText.isEmpty {
                    try? FileManager.default.removeItem(at: capture.url)
                    await handleTranscriptionFailure(
                        trigger: trigger,
                        message: "Nic se nepřepsalo — mluv hlasitěji."
                    )
                    return
                }

                // Aplikuj per-token replacement s tracking → finální slova (s originalText kde proběhla náhrada).
                let activeVocab = await MainActor.run { LearningEngine.shared.currentActiveVocabulary() }
                let replacedWords = activeVocab.applyReplacementsWithTracking(to: raw.words)
                let joinedText = replacedWords.map(\.text).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let caseWhitelist = TranscriptionCaseNormalizer.buildWhitelist(
                    vocabularyCanonicals: activeVocab.entries.map(\.canonical)
                )
                let caseNormalized = TranscriptionCaseNormalizer.normalize(joinedText, whitelist: caseWhitelist)
                let formatted = CzechDictationFormatter.format(
                    caseNormalized,
                    targetAppBundleID: targetApp?.bundleIdentifier
                )

                let finalText: String
                if PostProcessingPreference.isEnabled, await postProcessingEngine.isLoaded {
                    let processed: String? = await withTaskGroup(of: String?.self) { group in
                        group.addTask { [weak self] in
                            try? await self?.postProcessingEngine.process(
                                formatted,
                                targetAppBundleID: targetApp?.bundleIdentifier
                            )
                        }
                        group.addTask {
                            try? await Task.sleep(for: .milliseconds(7_000))
                            return nil
                        }
                        for await result in group {
                            group.cancelAll()
                            return result
                        }
                        return nil
                    }
                    if let processed {
                        finalText = processed.trimmingCharacters(in: .whitespacesAndNewlines)
                        DiagnosticsLogger.log("PostProcessing: applied (\(caseNormalized.count)c → \(finalText.count)c)")
                    } else {
                        finalText = formatted
                        DiagnosticsLogger.log("PostProcessing: timeout or error — using rule-based format")
                    }
                } else {
                    finalText = formatted
                }

                if finalText.isEmpty {
                    try? FileManager.default.removeItem(at: capture.url)
                    await handleTranscriptionFailure(
                        trigger: trigger,
                        message: "Nic se nepřepsalo — mluv hlasitěji."
                    )
                    return
                }

                let entryID = UUID()
                let cachedAudioURL = AudioCache.store(audioURL: capture.url, entryID: entryID)
                if cachedAudioURL == nil {
                    try? FileManager.default.removeItem(at: capture.url)
                }

                let entry = TranscriptionHistoryEntry(
                    id: entryID,
                    recordedAt: Date(),
                    text: finalText,
                    words: replacedWords,
                    audioCacheURL: cachedAudioURL,
                    targetAppBundleID: targetApp?.bundleIdentifier
                )

                DiagnosticsLogger.log("Transcription done (\(trigger)); len=\(finalText.count), words=\(replacedWords.count)")

                if trigger == "test" {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.transcriptionTestMode = false
                        self.stateMachine.transition(to: .idle)
                    }
                    self.showTranscriptionTestAlert(text: finalText, errorMessage: nil)
                    return
                }

                let injectExternally = dictationTargetTracker.shouldInjectExternally(into: targetApp)
                let reviewBeforePaste = DictationReviewPreference.isEnabled && injectExternally

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.publishLastTranscription(entry)
                    LearningEngine.shared.observeTranscriptionDone(entry: entry)
                    self.checkForRetryAndObserve(entry: entry)
                    SoundFeedbackService.playRecordingStop()
                    self.recordingOverlay.hide()
                    if reviewBeforePaste {
                        DiagnosticsLogger.log("Dictation (\(trigger)): review-before-paste")
                        self.stateMachine.transition(to: .idle)
                        self.presentLaunchHistory()
                        self.recordingOverlay.showTransientFeedback(
                            "Přepis v historii — zkontroluj.",
                            duration: 5
                        )
                    } else if injectExternally {
                        self.stateMachine.transition(to: .injecting)
                    } else {
                        DiagnosticsLogger.log("Dictation (\(trigger)): history only — skipping external inject")
                        self.stateMachine.transition(to: .idle)
                        self.presentLaunchHistory()
                        self.recordingOverlay.showTransientFeedback(
                            "Přepis v historii — klepni Vložit.",
                            duration: 4
                        )
                    }
                }

                guard injectExternally, !reviewBeforePaste else { return }

                let injectResult = await pasteWithWatchdog(text: finalText, into: targetApp, trigger: trigger)
                await MainActor.run { [weak self] in
                    self?.finalizeInjectUI(injectResult, trigger: trigger)
                    self?.stateMachine.transition(to: .idle)
                }
            } catch let error as TranscriptionError {
                try? FileManager.default.removeItem(at: capture.url)
                let message = transcriptionFailureMessage(for: error)
                DiagnosticsLogger.log("Transcription failed (\(trigger)): \(message)")
                await handleTranscriptionFailure(trigger: trigger, message: message)
            } catch {
                try? FileManager.default.removeItem(at: capture.url)
                logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                DiagnosticsLogger.log("Transcription failed (\(trigger)): \(error.localizedDescription)")
                await handleTranscriptionFailure(
                    trigger: trigger,
                    message: "Přepis selhal — zkus znovu."
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
            SoundFeedbackService.playError()
            self.recordingOverlay.hide()
            self.recordingOverlay.showTransientFeedback(message, duration: 5)
            self.statusBarController.showTransientStatus(message, duration: 6)
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
            return "Mikrofon skoro nic nezachytil — mluv blíž."
        case .hallucinatedTranscript:
            return "Jen šum — mluv hlasitěji."
        case .modelNotLoaded:
            return "Model se načítá — počkej."
        }
    }

    private func publishLastTranscription(_ entry: TranscriptionHistoryEntry) {
        lastTranscriptionText = entry.text
        transcriptionHistory.insert(entry, at: 0)
        if transcriptionHistory.count > maxTranscriptionHistoryCount {
            transcriptionHistory.removeSubrange(maxTranscriptionHistoryCount ..< transcriptionHistory.count)
        }
        scheduleHistoryPersist()
        pushTranscriptionHistoryToPanels()
    }

    private func pushTranscriptionHistoryToPanels() {
        launchWindowController?.setTranscriptionHistory(transcriptionHistory)
        historyWindowController?.setTranscriptionHistory(transcriptionHistory)
    }

    private func presentLaunchHistory() {
        launchWindowController?.setTranscriptionHistory(transcriptionHistory)
        launchWindowController?.focusTranscriptionPanel()
    }

    private func scheduleHistoryPersist() {
        historySaveTimer?.invalidate()
        let snapshot = transcriptionHistory
        historySaveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            HistoryStore.save(snapshot)
        }
    }

    private func pushLearningSnapshotToEngine() {
        let snapshot = LearningEngine.shared.currentActiveVocabulary()
        Task { [weak self] in
            await self?.transcriptionEngine.applyVocabulary(snapshot)
        }
    }

    /// Pokud poslední přepis proběhl <8 s a vypadá jako retry předchozího, předáme dvojici
    /// `LearningEngine.observeRetry` — ten může zapsat pending kandidáta varianta→canonical.
    private func checkForRetryAndObserve(entry: TranscriptionHistoryEntry) {
        if let last = lastDictation,
           Date().timeIntervalSince(last.recordedAt) <= retryWindow {
            LearningEngine.shared.observeRetry(previous: last.entry, current: entry)
        }
        lastDictation = (entry: entry, recordedAt: Date())
    }

    private func showLastTranscription() {
        guard let lastTranscriptionText, !lastTranscriptionText.isEmpty else {
            statusBarController.showTransientStatus("Zatím žádný přepis — nejdřív něco nadiktuj", duration: 3)
            return
        }
        presentLaunchHistory()
    }

    private func showTranscriptionPopover(from statusButton: NSStatusBarButton) {
        let entry = transcriptionHistory.first
        statusBarPopover.show(
            relativeTo: statusButton,
            entry: entry,
            onCopy: { [weak self] in
                guard let text = entry?.text else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self?.statusBarController.showTransientStatus("Zkopírováno", duration: 2)
            },
            onInsert: { [weak self] in
                guard let text = entry?.text else { return }
                self?.startBackgroundInject(text: text, trigger: "menu-popover")
            },
            onOpenFullHistory: { [weak self] in
                self?.showLastTranscription()
            }
        )
    }

    /// Runs paste pipeline with a watchdog; safe from any executor.
    private func pasteWithWatchdog(text: String, into targetApp: NSRunningApplication?, trigger: String) async -> TextInjectResult {
        let watchdog = DispatchWorkItem { [weak self] in
            DiagnosticsLogger.log("Inject watchdog: background inject exceeded 5s (\(trigger))")
            Task { @MainActor in
                guard let self else { return }
                SoundFeedbackService.playError()
                self.recordingOverlay.showTransientFeedback(
                    "Vkládání trvá dlouho…",
                    duration: 5
                )
                self.statusBarController.showTransientStatus(
                    "Vkládání trvá dlouho…",
                    duration: 4
                )
            }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5, execute: watchdog)
        defer { watchdog.cancel() }

        await waitForDictationHotkeyReleaseIfNeeded()
        try? await Task.sleep(for: .milliseconds(150))
        return await TextInjector.inject(text: text, into: targetApp)
    }

    /// Po puštění pravého ⌘ jako hotkey musíme počkat, než se modifier uvolní — jinak Cmd+V selže.
    private func waitForDictationHotkeyReleaseIfNeeded() async {
        guard HotkeyPreference.current == .rightCommand else { return }
        let keyCode: CGKeyCode = 54
        for _ in 0..<60 {
            if !CGEventSource.keyState(.hidSystemState, key: keyCode) { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    private func finalizeInjectUI(_ injectResult: TextInjectResult, trigger: String) {
        if injectResult.succeeded {
            DiagnosticsLogger.log("Paste: background inject succeeded (\(trigger))")
            recordingOverlay.show(.injectionSuccess)
            recordingOverlay.scheduleAutoHide(after: 0.7)
        } else {
            DiagnosticsLogger.log("Paste: background inject failed (\(trigger))")
            SoundFeedbackService.playError()
            let reason: String
            if case .failed(let message) = injectResult {
                reason = message
            } else {
                reason = "Text se nevložil"
            }
            recordingOverlay.show(.injectionFailed(reason))
            recordingOverlay.scheduleAutoHide(after: 5)
            showLastTranscription()
            statusBarController.showTransientStatus(
                "Vložení selhalo — text je v historii.",
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
            return "Počkej — vkládám"
        case .transcribing:
            return "Přepisuji…"
        case .modelDownloading, .modelLoading:
            return "Načítám model…"
        default:
            return "Počkej…"
        }
    }

    private func showLearnedTermsWindow() {
        if learnedTermsWindowController == nil {
            learnedTermsWindowController = LearnedTermsWindowController()
        }
        learnedTermsWindowController?.showWindow(nil)
    }

    private func runAccessibilityAudit() {
        let menu = statusBarController.statusButton?.menu
        let context = AccessibilityAuditEngine.AuditContext(
            openWindowTitles: NSApp.windows.map { $0.title.isEmpty ? "(bez titulku)" : $0.title },
            axTrusted: AccessibilitySettings.isTrusted(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            bundlePath: Bundle.main.bundleURL.path
        )
        if let url = AccessibilityAuditEngine.runAndSaveReport(extraMenu: menu, context: context) {
            statusBarController.showTransientStatus("Analýza zpřístupnění uložena", duration: 4)
            AccessibilityAuditEngine.openLatestReportInFinder()
            DiagnosticsLogger.log("Accessibility audit exported: \(url.lastPathComponent)")
        } else {
            statusBarController.showTransientStatus("Analýzu se nepodařilo uložit", duration: 4)
        }
    }

    private func startAudioLevelMeterUpdates() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { [weak self] in
                guard let self, self.stateMachine.isRecording else { return }
                let level = await self.audioRecorder.recentLiveLevel()
                let normalized = min(1, level / 0.02)
                await MainActor.run {
                    self.recordingOverlay.updateAudioLevel(normalized)
                }
            }
        }
    }

    private func stopAudioLevelMeterUpdates() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        recordingOverlay.updateAudioLevel(0)
    }

    private func showSetupWindow() {
        setupWindowController?.close()
        let controller = SetupWindowController()
        controller.onPermissionsGranted = { [weak self] in
            self?.setupWindowController = nil
            self?.hotkeyManager.reinstallAfterAccessibilityGrant()
            self?.startStartupTask()
        }
        setupWindowController = controller
        AppWindowPresenter.present(controller.window)
    }

    private func showPreferencesWindow() {
        if preferencesWindowController == nil {
            let controller = PreferencesWindowController()
            controller.hotkeyHealthProvider = { [weak self] in
                self?.hotkeyManager.currentHealth() ?? .tapMissing
            }
            preferencesWindowController = controller
        } else {
            preferencesWindowController?.hotkeyHealthProvider = { [weak self] in
                self?.hotkeyManager.currentHealth() ?? .tapMissing
            }
        }
        AppWindowPresenter.present(preferencesWindowController?.window)
    }

    private func startPostProcessingLoad() async {
        guard PostProcessingPreference.isEnabled else { return }
        guard await !postProcessingEngine.isLoaded else { return }
        DiagnosticsLogger.log("PostProcessing: background load starting")
        do {
            try await postProcessingEngine.load { [weak self] progress in
                Task { @MainActor in
                    let pct = Int(progress * 100)
                    self?.statusBarController.showTransientStatus("Oprava textu: načítám (\(pct) %)", duration: 3)
                }
            }
            await MainActor.run { [weak self] in
                self?.statusBarController.showTransientStatus("Oprava textu: připraveno", duration: 4)
            }
        } catch {
            DiagnosticsLogger.log("PostProcessing: background load failed — \(error.localizedDescription)")
        }
    }

    private func handlePostProcessingPreferenceChanged() {
        if PostProcessingPreference.isEnabled {
            Task { [weak self] in await self?.startPostProcessingLoad() }
        } else {
            Task { [weak self] in await self?.postProcessingEngine.unload() }
        }
    }

    private func handleTranscriptionModelPreferenceChanged() {
        guard !stateMachine.isRecording else { return }
        DiagnosticsLogger.log(
            "Transcription model preference changed to \(TranscriptionModelPreference.current.rawValue)"
        )
        Task {
            await transcriptionEngine.unload()
            if PermissionsSnapshotProvider.current.allGranted {
                startStartupTask()
            }
        }
    }

    private func startStreamingPipelineIfPossible() async {
        do {
            try await ensureTranscriptionEngineReady()
            try await transcriptionEngine.beginStreaming()
        } catch {
            DiagnosticsLogger.log("Streaming pipeline unavailable: \(error.localizedDescription)")
            return
        }

        await audioRecorder.setSamplesUpdateHandler { [weak self] in
            Task { @MainActor in
                self?.scheduleStreamingPartialUpdate()
            }
        }

        streamingTranscriptionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                await self?.runStreamingPartialUpdate()
            }
        }
    }

    private func scheduleStreamingPartialUpdate() {
        Task { @MainActor [weak self] in
            await self?.runStreamingPartialUpdate()
        }
    }

    private func runStreamingPartialUpdate() async {
        guard DictationPreviewPreference.isEnabled else { return }
        guard stateMachine.isRecording else { return }
        let samples = await audioRecorder.currentAudioSamples()
        guard !samples.isEmpty else { return }
        guard let preview = await transcriptionEngine.streamingPreview(for: samples) else { return }
        guard !preview.displayText.isEmpty else { return }
        recordingOverlay.updateStreamingPreview(preview)
    }

    private func modelLoadErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain || error.localizedDescription.localizedCaseInsensitiveContains("offline") {
            return "Model se nestáhl — připoj internet a zkus znovu."
        }
        return "Model se nepodařilo načíst — zkus znovu."
    }
}
