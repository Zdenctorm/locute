import AppKit

@MainActor
final class TranscriptionTestSheet {
    private var panel: NSPanel?
    private var storedText = ""
    private var onDismiss: (() -> Void)?

    func present(text: String?, errorMessage: String?, onDismiss: @escaping () -> Void) {
        dismiss()
        self.onDismiss = onDismiss
        storedText = text ?? ""

        let width: CGFloat = 480
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        AppTheme.configureMainWindow(panel, title: "Ověření přepisu")

        let title = AppTheme.label(
            errorMessage == nil ? "Výsledek testu" : "Test se nepovedl",
            font: AppTheme.Font.headline,
            color: AppTheme.Color.title
        )

        let body = AppTheme.label(
            errorMessage ?? text ?? "",
            font: AppTheme.Font.body,
            color: errorMessage == nil ? AppTheme.Color.body : AppTheme.Color.danger,
            lines: 0
        )

        let copyButton = AppTheme.secondaryButton("Zkopírovat", target: self, action: #selector(copyTapped))
        copyButton.isEnabled = errorMessage == nil && !storedText.isEmpty

        let closeButton = AppTheme.primaryButton("Zavřít", target: self, action: #selector(closeTapped))

        let buttons = NSStackView(views: [copyButton, closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = AppTheme.Spacing.row

        let stack = NSStackView(views: [title, body, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = AppTheme.Spacing.row
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 280))
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
            body.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        panel.contentView = root
        panel.isReleasedWhenClosed = false
        self.panel = panel
        AppWindowPresenter.present(panel)
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }

    @objc private func copyTapped() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(storedText, forType: .string)
    }

    @objc private func closeTapped() {
        let completion = onDismiss
        onDismiss = nil
        dismiss()
        completion?()
    }
}
