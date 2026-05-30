import AppKit

@MainActor
final class StatusBarPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let previewLabel = NSTextField(wrappingLabelWithString: "")
    private let timestampLabel = NSTextField(labelWithString: "")
    private var onCopy: (() -> Void)?
    private var onInsert: (() -> Void)?
    private var onOpenFullHistory: (() -> Void)?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 200)
        let controller = NSViewController()
        controller.view = buildContent()
        popover.contentViewController = controller
    }

    func show(
        relativeTo statusButton: NSStatusBarButton,
        entry: TranscriptionHistoryEntry?,
        onCopy: @escaping () -> Void,
        onInsert: @escaping () -> Void,
        onOpenFullHistory: @escaping () -> Void
    ) {
        self.onCopy = onCopy
        self.onInsert = onInsert
        self.onOpenFullHistory = onOpenFullHistory

        if let entry {
            previewLabel.stringValue = entry.text
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "cs_CZ")
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            timestampLabel.stringValue = formatter.string(from: entry.recordedAt)
            timestampLabel.isHidden = false
        } else {
            previewLabel.stringValue = "Zatím žádný přepis. Podrž \(HotkeyPreference.current.hintLabel) a mluv."
            timestampLabel.isHidden = true
        }

        if popover.isShown {
            popover.performClose(nil)
        }
        popover.show(relativeTo: statusButton.bounds, of: statusButton, preferredEdge: .minY)
    }

    func close() {
        popover.performClose(nil)
    }

    private func buildContent() -> NSView {
        let title = AppTheme.label("Poslední přepis", font: AppTheme.Font.headline, color: AppTheme.Color.title)
        previewLabel.font = AppTheme.Font.body
        previewLabel.textColor = AppTheme.Color.body
        previewLabel.maximumNumberOfLines = 8
        previewLabel.lineBreakMode = .byWordWrapping

        timestampLabel.font = AppTheme.Font.footnote
        timestampLabel.textColor = AppTheme.Color.body

        let copyButton = AppTheme.secondaryButton("Zkopírovat", target: self, action: #selector(copyTapped))
        let insertButton = AppTheme.primaryButton("Vložit", target: self, action: #selector(insertTapped))
        let buttons = NSStackView(views: [copyButton, insertButton])
        buttons.orientation = .horizontal
        buttons.spacing = AppTheme.Spacing.row

        let historyButton = AppTheme.secondaryButton(
            "Otevřít celou historii…",
            target: self,
            action: #selector(openFullHistoryTapped)
        )

        let stack = NSStackView(views: [title, timestampLabel, previewLabel, buttons, historyButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = AppTheme.Spacing.tight
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = AppTheme.popoverRootView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        stack.edgeInsets = NSEdgeInsets(
            top: AppTheme.Spacing.section,
            left: AppTheme.Spacing.section,
            bottom: AppTheme.Spacing.section,
            right: AppTheme.Spacing.section
        )
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor)
        ])
        return root
    }

    @objc private func copyTapped() {
        onCopy?()
        close()
    }

    @objc private func insertTapped() {
        onInsert?()
        close()
    }

    @objc private func openFullHistoryTapped() {
        onOpenFullHistory?()
        close()
    }
}
