import Cocoa

/// Historie přepisů — samostatné okno na vyžádání (menu, popover, review-before-paste).
@MainActor
final class HistoryWindowController: NSWindowController {
    var onRetryInsert: ((String) -> Void)?

    private let transcriptionPanel = TranscriptionPanelView()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        AppTheme.configureMainWindow(window, title: "Historie přepisů")

        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        AppWindowPresenter.present(window)
        transcriptionPanel.scrollToLatestEntry()
    }

    func setTranscriptionHistory(_ entries: [TranscriptionHistoryEntry]) {
        transcriptionPanel.setHistory(entries)
    }

    private func buildUI() {
        transcriptionPanel.onInsert = { [weak self] text in
            self?.onRetryInsert?(text)
        }

        let helper = AppTheme.label(
            "Záloha a opravy slov. Poslední přepis otevřeš také z menu baru — „Poslední přepis…“.",
            font: AppTheme.Font.footnote,
            color: AppTheme.Color.body,
            lines: 0
        )

        let closeButton = AppTheme.primaryButton("Zavřít", target: self, action: #selector(closeWindow))
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        window?.contentView = contentView

        transcriptionPanel.translatesAutoresizingMaskIntoConstraints = false
        helper.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(transcriptionPanel)
        contentView.addSubview(helper)
        contentView.addSubview(closeButton)

        let pad = AppTheme.Spacing.windowPadding
        NSLayoutConstraint.activate([
            transcriptionPanel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: pad),
            transcriptionPanel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            transcriptionPanel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),

            helper.topAnchor.constraint(equalTo: transcriptionPanel.bottomAnchor, constant: AppTheme.Spacing.row),
            helper.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            helper.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),

            closeButton.topAnchor.constraint(equalTo: helper.bottomAnchor, constant: AppTheme.Spacing.stack),
            closeButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            closeButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -pad)
        ])
    }

    @objc private func closeWindow() {
        window?.orderOut(nil)
    }
}
