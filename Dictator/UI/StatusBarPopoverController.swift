import AppKit

@MainActor
final class StatusBarPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let previewLabel = NSTextField(wrappingLabelWithString: "")
    private let timestampLabel = NSTextField(labelWithString: "")
    private let copyButton = AppTheme.primaryButton("Zkopírovat", target: nil, action: nil)
    private var onCopy: (() -> Void)?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 200)
        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        let controller = NSViewController()
        controller.view = buildContent()
        popover.contentViewController = controller
    }

    func show(
        relativeTo statusButton: NSStatusBarButton,
        entry: TranscriptionHistoryEntry?,
        onCopy: @escaping () -> Void
    ) {
        self.onCopy = onCopy

        if let entry, !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            previewLabel.stringValue = entry.text
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "cs_CZ")
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            timestampLabel.stringValue = formatter.string(from: entry.recordedAt)
            timestampLabel.isHidden = false
            copyButton.isEnabled = true
        } else {
            previewLabel.stringValue = "Zatím žádný přepis. Podrž diktovací klávesu a mluv."
            timestampLabel.isHidden = true
            copyButton.isEnabled = false
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

        let buttons = NSStackView(views: [copyButton])
        buttons.orientation = .horizontal
        buttons.spacing = AppTheme.Spacing.row

        let stack = NSStackView(views: [title, timestampLabel, previewLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = AppTheme.Spacing.tight
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
            timestampLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            previewLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return root
    }

    @objc private func copyTapped() {
        onCopy?()
        close()
    }
}
