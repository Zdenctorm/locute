import AppKit

/// Kontejner s origin nahoře vlevo — scroll view na macOS jinak „sežere“ levý padding.
private final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
enum ScrollContentLayout {
    struct Configuration {
        var horizontalPadding: CGFloat = AppTheme.Spacing.windowPadding
        var verticalPadding: CGFloat = AppTheme.Spacing.windowPadding
        var stackSpacing: CGFloat = AppTheme.Spacing.stack
    }

    static func install(
        in scrollView: NSScrollView,
        arrangedSubviews: [NSView],
        config: Configuration = Configuration()
    ) -> NSStackView {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .windowBackgroundColor
        if #available(macOS 11.0, *) {
            scrollView.automaticallyAdjustsContentInsets = true
        }

        let document = FlippedContainerView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        let stack = NSStackView(views: arrangedSubviews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = config.stackSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        let padH = config.horizontalPadding
        let padV = config.verticalPadding

        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.topAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: padH),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -padH),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: padV),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -padV)
        ])

        for view in arrangedSubviews {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        return stack
    }
}
