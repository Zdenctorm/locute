import Cocoa
import Combine

@MainActor
final class LaunchWindowController: NSWindowController {
    var onRetry: (() -> Void)?
    var onRetryInsert: ((String) -> Void)?

    private let stateMachine: AppStateMachine
    private var cancellables = Set<AnyCancellable>()
    private var modelLoadStartedAt: Date?
    private var modelLoadTimer: Timer?
    private let statusLabel = NSTextField(labelWithString: "Starting")
    private let downloadTitleLabel = AppTheme.label("", font: AppTheme.Font.headline, color: AppTheme.Color.title)
    private let downloadProgressIndicator = NSProgressIndicator()
    private let downloadDetailLabel = AppTheme.label("", font: AppTheme.Font.body, color: AppTheme.Color.body, lines: 0)
    private var downloadCard: NSView?
    private var latestDownloadProgress = ModelDownloadProgress.empty
    private let retryButton = AppTheme.primaryButton("Zkusit znovu", target: nil, action: nil)
    private let transcriptionPanel = TranscriptionPanelView()
    private var transcriptionCard: NSView!

    init(stateMachine: AppStateMachine) {
        self.stateMachine = stateMachine

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        AppTheme.configureMainWindow(window, title: AppBrand.displayName)

        super.init(window: window)
        buildUI()
        observeState()
        update(for: stateMachine.state)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        AppWindowPresenter.present(window)
    }

    func setTranscriptionHistory(_ entries: [TranscriptionHistoryEntry]) {
        transcriptionPanel.setHistory(entries)
    }

    func focusTranscriptionPanel() {
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

        let detail = AppTheme.label(
            "Soukromé diktování v češtině. Podržte \(HotkeyPreference.current.hintLabel), mluvte a pusťte — text se vloží do aplikace, kde máte kurzor. Historie přepisů je níže (záloha a opravy slov).",
            font: AppTheme.Font.body,
            color: AppTheme.Color.body,
            lines: 0
        )

        statusLabel.font = AppTheme.Font.status
        statusLabel.textColor = AppTheme.Color.title
        statusLabel.maximumNumberOfLines = 0

        downloadProgressIndicator.minValue = 0
        downloadProgressIndicator.maxValue = 1
        downloadProgressIndicator.doubleValue = 0
        downloadProgressIndicator.isIndeterminate = false
        downloadProgressIndicator.style = .bar
        downloadProgressIndicator.controlSize = .regular

        transcriptionCard = transcriptionPanel
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

        let closeButton = AppTheme.primaryButton("Skrýt okno", target: self, action: #selector(hideWindow))
        retryButton.target = self
        retryButton.action = #selector(retry)
        retryButton.isHidden = true

        let actions = NSStackView(views: [retryButton, closeButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = AppTheme.Spacing.row

        let headerText = NSStackView(views: [title, detail])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = AppTheme.Spacing.tight
        headerText.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [logo, headerText])
        header.orientation = .horizontal
        header.alignment = .top
        header.spacing = AppTheme.Spacing.stack
        header.translatesAutoresizingMaskIntoConstraints = false
        headerText.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Window layout: header pinned to top, bottomStack pinned to bottom, transcript panel
        // fills the middle and grows with the window. No outer scroll — the transcript panel
        // has its own internal scroll for entries, so single-scroll experience.
        let contentView = NSView()
        window?.contentView = contentView

        let bottomStack = NSStackView(views: [modelCard, statusLabel, actions])
        bottomStack.orientation = .vertical
        bottomStack.alignment = .leading
        bottomStack.spacing = AppTheme.Spacing.stack
        bottomStack.setCustomSpacing(AppTheme.Spacing.intimate, after: statusLabel)
        bottomStack.translatesAutoresizingMaskIntoConstraints = false

        header.translatesAutoresizingMaskIntoConstraints = false
        transcriptionCard.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(header)
        contentView.addSubview(transcriptionCard)
        contentView.addSubview(bottomStack)

        let pad = AppTheme.Spacing.windowPadding
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: contentView.topAnchor, constant: pad),
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),

            transcriptionCard.topAnchor.constraint(equalTo: header.bottomAnchor, constant: AppTheme.Spacing.hero),
            transcriptionCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            transcriptionCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),
            transcriptionCard.bottomAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -AppTheme.Spacing.stack),

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

    private func update(for state: DictatorState) {
        switch state {
        case .idle:
            statusLabel.stringValue = "Připraveno. Okno můžete skrýt, \(AppBrand.displayName) zůstane dostupný v horní liště."
            statusLabel.textColor = AppTheme.Color.title
            retryButton.isHidden = true
        case .modelDownloading(let progress):
            if modelLoadStartedAt == nil {
                modelLoadStartedAt = Date()
                startModelLoadTimer()
            }
            latestDownloadProgress = progress
            downloadCard?.isHidden = false
            downloadProgressIndicator.doubleValue = progress.fraction
            updateModelLoadMessage()
            statusLabel.textColor = AppTheme.Color.title
            retryButton.isHidden = true
        case .modelLoading:
            stopModelLoadTimer()
            downloadCard?.isHidden = true
            statusLabel.stringValue = "Model je stažený. Připravuji lokální přepis."
            statusLabel.textColor = AppTheme.Color.title
            retryButton.isHidden = true
        case .permissionsNeeded:
            stopModelLoadTimer()
            downloadCard?.isHidden = true
            statusLabel.stringValue = "Je potřeba povolit mikrofon a Zpřístupnění."
            statusLabel.textColor = AppTheme.Color.title
            retryButton.isHidden = true
        case .error(let message):
            stopModelLoadTimer()
            downloadCard?.isHidden = true
            statusLabel.stringValue = message
            statusLabel.textColor = AppTheme.Color.danger
            retryButton.isHidden = false
        default:
            stopModelLoadTimer()
            downloadCard?.isHidden = true
            statusLabel.stringValue = state.displayText
            statusLabel.textColor = AppTheme.Color.title
            retryButton.isHidden = true
        }
    }

    @objc private func hideWindow() {
        window?.orderOut(nil)
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
        downloadTitleLabel.stringValue = "Stahuji Whisper (\(preference.label))"
        let elapsed = Int(Date().timeIntervalSince(modelLoadStartedAt ?? Date()))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        let elapsedText = minutes > 0 ? "\(minutes) min \(seconds) s" : "\(seconds) s"
        let downloaded = Self.byteFormatter.string(fromByteCount: latestDownloadProgress.downloadedBytes)
        let total = Self.byteFormatter.string(fromByteCount: latestDownloadProgress.totalBytes)
        let percent = Int((latestDownloadProgress.fraction * 100).rounded())

        downloadDetailLabel.stringValue = "Staženo \(downloaded) z \(total) (\(percent) %)."
        statusLabel.stringValue = "První spuštění stahuje lokální model (~\(preference.label.lowercased())). Můžete už diktovat — přepis dokončíme po stažení. Příště se model nestahuje. Probíhá už \(elapsedText). Nezavírejte aplikaci."
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
