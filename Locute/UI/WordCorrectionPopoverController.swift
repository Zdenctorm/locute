import Cocoa

@MainActor
final class WordCorrectionPopoverController: NSObject, NSPopoverDelegate {
    static let shared = WordCorrectionPopoverController()

    var onLearned: ((String) -> Void)?

    private let popover = NSPopover()
    private let heardField = NSTextField()
    private let correctField = NSTextField()
    private var pendingWord: WordToken?

    private override init() {
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 320, height: 148)
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = buildContent()
    }

    func present(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        preferredEdge: NSRectEdge = .maxY,
        word: WordToken
    ) {
        pendingWord = word
        heardField.stringValue = word.originalText ?? word.text
        correctField.stringValue = ""
        popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: preferredEdge)
        positioningView.window?.makeFirstResponder(correctField)
    }

    func close() {
        popover.performClose(nil)
    }

    private func buildContent() -> NSView {
        let heardLabel = AppTheme.label("Toto slovo:", font: AppTheme.Font.footnote, color: AppTheme.Color.body)
        heardField.isEditable = false
        heardField.isSelectable = true
        heardField.isBezeled = true
        heardField.bezelStyle = .roundedBezel
        heardField.font = AppTheme.Font.body
        heardField.translatesAutoresizingMaskIntoConstraints = false

        let correctLabel = AppTheme.label("Mělo by být:", font: AppTheme.Font.footnote, color: AppTheme.Color.body)
        correctField.placeholderString = "Správný tvar"
        correctField.font = AppTheme.Font.body
        correctField.translatesAutoresizingMaskIntoConstraints = false

        let learnButton = AppTheme.primaryButton("Naučit", target: self, action: #selector(learnTapped))
        let cancelButton = AppTheme.secondaryButton("Zrušit", target: self, action: #selector(cancelTapped))

        let buttons = NSStackView(views: [cancelButton, learnButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = AppTheme.Spacing.row
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [heardLabel, heardField, correctLabel, correctField, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = AppTheme.Spacing.tight
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(
            top: AppTheme.Spacing.section,
            left: AppTheme.Spacing.section,
            bottom: AppTheme.Spacing.section,
            right: AppTheme.Spacing.section
        )

        let container = AppTheme.popoverRootView()
        AccessibilitySupport.configure(
            container,
            label: "Oprava slova",
            help: "Uprav správný tvar slova a zvol Naučit.",
            role: .group
        )
        heardField.setAccessibilityLabel("Slovo z přepisu")
        correctField.setAccessibilityLabel("Správný tvar")
        correctField.setAccessibilityHelp("Napiš, jak má slovo znít. Potom zvol Naučit.")

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            heardField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            correctField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
        return container
    }

    @objc private func learnTapped() {
        guard let word = pendingWord else {
            close()
            return
        }
        let canonical = correctField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty else {
            correctField.shake()
            return
        }
        let variant = (word.originalText ?? word.text).trimmingCharacters(in: .whitespacesAndNewlines)
        LearningEngine.shared.observeUserCorrection(
            variant: variant,
            canonical: canonical,
            source: .userClickInHistory
        )
        onLearned?(canonical)
        close()
    }

    @objc private func cancelTapped() {
        close()
    }
}

private extension NSTextField {
    func shake() {
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        animation.values = [0, -6, 6, -4, 4, 0]
        animation.isAdditive = true
        animation.duration = 0.35
        layer?.add(animation, forKey: "shake")
    }
}
