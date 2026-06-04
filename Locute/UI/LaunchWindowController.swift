import Cocoa
import Combine

/// Domovské okno: stav při startu/stahování modelu + historie přepisů (Glimpse/Whispur recovery pattern).
@MainActor
final class LaunchWindowController: NSWindowController {
    var onRetry: (() -> Void)?
    var onRetryInsert: ((String) -> Void)?
    var onOpenSetupGuide: (() -> Void)?

    private let stateMachine: AppStateMachine
    private var cancellables = Set<AnyCancellable>()
    private var modelLoadStartedAt: Date?
    private var modelLoadTimer: Timer?
    private let heroDetailLabel = AppTheme.label(
        "",
        font: AppTheme.Font.body,
        color: AppTheme.Color.body,
        lines: 0
    )
    private let statusLabel = AppTheme.label(
        "Spouštím…",
        font: AppTheme.Font.status,
        color: AppTheme.Color.title,
        lines: 0
    )
    private var hotkeyObserver: NSObjectProtocol?
    private let downloadTitleLabel = AppTheme.label("", font: AppTheme.Font.headline, color: AppTheme.Color.title)
    private let downloadProgressIndicator = NSProgressIndicator()
    private let downloadDetailLabel = AppTheme.label("", font: AppTheme.Font.body, color: AppTheme.Color.body, lines: 0)
    private var downloadCard: NSView?
    private var latestDownloadProgress = ModelDownloadProgress.empty
    private let retryButton = AppTheme.primaryButton("Zkusit znovu", target: nil, action: nil)
    private let setupGuideButton = AppTheme.primaryButton("Průvodce nastavením…", target: nil, action: nil)
    private let closeButton = AppTheme.secondaryButton("Skrýt okno", target: nil, action: nil)
    private let transcriptionPanel = TranscriptionPanelView()

    init(stateMachine: AppStateMachine) {
        self.stateMachine = stateMachine

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        AppTheme.configureMainWindow(window, title: AppBrand.displayName)
        window.minSize = NSSize(width: 480, height: 360)
        window.contentMinSize = NSSize(width: 480, height: 360)

        super.init(window: window)
        buildUI()
        observeState()
        refreshHotkeyCopy()
        update(for: stateMachine.state)
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .locuteHotkeyPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshHotkeyCopy()
            }
        }
    }

    deinit {
        if let hotkeyObserver {
            NotificationCenter.default.removeObserver(hotkeyObserver)
        }
    }

    private func refreshHotkeyCopy() {
        heroDetailLabel.stringValue =
            "Podrž \(HotkeyPreference.current.hintLabel), mluv, pusť. Historie je níže."
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        AppWindowPresenter.presentHome(window)
    }

    func setTranscriptionHistory(_ entries: [TranscriptionHistoryEntry]) {
        transcriptionPanel.setHistory(entries)
    }

    func focusTranscriptionPanel() {
        transcriptionPanel.scrollToLatestEntry()
        showWindow(nil)
    }

    private func buildUI() {
        let logo = AppLogoView()
        logo.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 64),
            logo.heightAnchor.constraint(equalToConstant: 64)
        ])

        let title = AppTheme.label("\(AppBrand.displayName) běží", font: AppTheme.Font.largeTitle, color: AppTheme.Color.title)

        AccessibilitySupport.configure(statusLabel, label: "Stav aplikace")
        AccessibilitySupport.configure(downloadProgressIndicator, label: "Průběh stahování modelu")

        downloadProgressIndicator.minValue = 0
        downloadProgressIndicator.maxValue = 1
        downloadProgressIndicator.doubleValue = 0
        downloadProgressIndicator.isIndeterminate = false
        downloadProgressIndicator.style = .bar
        downloadProgressIndicator.controlSize = .regular

        transcriptionPanel.onInsert = { [weak self] text in
            self?.onRetryInsert?(text)
        }

        let modelCard = AppTheme.card([
            downloadTitleLabel,
            downloadProgressIndicator,
            downloadDetailLabel
        ])
        modelCard.isHidden = true
        downloadCard = modelCard

        retryButton.target = self
        retryButton.action = #selector(retry)
        retryButton.isHidden = true

        setupGuideButton.target = self
        setupGuideButton.action = #selector(openSetupGuide)
        setupGuideButton.isHidden = true

        closeButton.target = self
        closeButton.action = #selector(hideWindow)

        let actions = NSStackView(views: [retryButton, setupGuideButton, closeButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = AppTheme.Spacing.row

        let headerText = NSStackView(views: [title, heroDetailLabel])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = AppTheme.Spacing.tight
        headerText.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [logo, headerText])
        header.orientation = .horizontal
        header.alignment = .top
        header.spacing = AppTheme.Spacing.stack
        header.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        window?.contentView = contentView

        let bottomStack = NSStackView(views: [modelCard, statusLabel, actions])
        bottomStack.orientation = .vertical
        bottomStack.alignment = .leading
        bottomStack.spacing = AppTheme.Spacing.stack
        bottomStack.setCustomSpacing(AppTheme.Spacing.intimate, after: statusLabel)
        bottomStack.translatesAutoresizingMaskIntoConstraints = false

        transcriptionPanel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(header)
        contentView.addSubview(transcriptionPanel)
        contentView.addSubview(bottomStack)

        let pad = AppTheme.Spacing.windowPadding
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: contentView.topAnchor, constant: pad),
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),

            transcriptionPanel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: AppTheme.Spacing.hero),
            transcriptionPanel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            transcriptionPanel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),
            transcriptionPanel.bottomAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -AppTheme.Spacing.stack),

            bottomStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            bottomStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),
            bottomStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -pad),

            modelCard.widthAnchor.constraint(equalTo: bottomStack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: bottomStack.widthAnchor)
        ])
    }

    private func observeState() {
        stateMachine.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.update(for: state) }
            .store(in: &cancellables)
    }

    private func update(for state: LocuteState) {
        switch state {
        case .idle:
            statusLabel.stringValue = "Připraveno."
            statusLabel.textColor = AppTheme.Color.title
            setupGuideButton.isHidden = true
            retryButton.isHidden = true
        case .modelDownloading(let progress):
            if modelLoadStartedAt == nil {
                modelLoadStartedAt = Date()
                startModelLoadTimer()
            }
            latestDownloadProgress = progress
            downloadCard?.isHidden = false
            downloadProgressIndicator.doubleValue = progress.fraction
            let pct = Int(progress.fraction * 100)
            downloadProgressIndicator.setAccessibilityValue("\(pct) procent")
            updateModelLoadMessage()
            statusLabel.textColor = AppTheme.Color.title
            setupGuideButton.isHidden = true
            retryButton.isHidden = true
        case .modelLoading:
            stopModelLoadTimer()
            downloadCard?.isHidden = true
            statusLabel.stringValue = "Načítám model…"
            statusLabel.textColor = AppTheme.Color.title
            setupGuideButton.isHidden = true
            retryButton.isHidden = true
        case .permissionsNeeded:
            stopModelLoadTimer()
            downloadCard?.isHidden = true
            statusLabel.stringValue = "Chybí oprávnění — otevři průvodce."
            statusLabel.textColor = AppTheme.Color.warning
            setupGuideButton.isHidden = false
            retryButton.isHidden = true
        case .error(let message):
            stopModelLoadTimer()
            downloadCard?.isHidden = true
            statusLabel.stringValue = message
            statusLabel.textColor = AppTheme.Color.danger
            AccessibilitySupport.announce("Chyba: \(message)")
            setupGuideButton.isHidden = true
            retryButton.isHidden = false
        default:
            stopModelLoadTimer()
            downloadCard?.isHidden = true
            statusLabel.stringValue = state.displayText
            statusLabel.textColor = AppTheme.Color.title
            setupGuideButton.isHidden = true
            retryButton.isHidden = true
        }
    }

    @objc private func hideWindow() {
        window?.orderOut(nil)
    }

    @objc private func openSetupGuide() {
        onOpenSetupGuide?()
    }

    @objc private func retry() {
        stopModelLoadTimer()
        retryButton.isHidden = true
        onRetry?()
    }

    private func startModelLoadTimer() {
        modelLoadTimer?.invalidate()
        modelLoadTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateModelLoadMessage() }
        }
    }

    private func stopModelLoadTimer() {
        modelLoadTimer?.invalidate()
        modelLoadTimer = nil
        modelLoadStartedAt = nil
    }

    private func updateModelLoadMessage() {
        let preference = TranscriptionModelPreference.current
        downloadTitleLabel.stringValue = "Stahuji lokální model (\(preference.label))"
        let elapsed = Int(Date().timeIntervalSince(modelLoadStartedAt ?? Date()))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        let elapsedText = minutes > 0 ? "\(minutes) min \(seconds) s" : "\(seconds) s"
        let downloaded = Self.byteFormatter.string(fromByteCount: latestDownloadProgress.downloadedBytes)
        let total = Self.byteFormatter.string(fromByteCount: latestDownloadProgress.totalBytes)
        let percent = Int((latestDownloadProgress.fraction * 100).rounded())

        downloadDetailLabel.stringValue = "\(downloaded) / \(total) (\(percent) %)."
        statusLabel.stringValue = "Stahuji model (\(elapsedText)). Můžeš už diktovat."
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}
