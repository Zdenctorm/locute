import Cocoa

enum AppTheme {
    enum Spacing {
        static let windowPadding: CGFloat = 40
        static let stack: CGFloat = 20
        /// Větší gap po brand headeru, ať hero dýchá ostřeji než pomocné moduly.
        static let hero: CGFloat = 32
        /// Menší gap pro pomocné prvky pod sebou (footer + helper text).
        static let intimate: CGFloat = 8
        static let row: CGFloat = 12
        static let tight: CGFloat = 6
        static let cardPadding: CGFloat = 24
        static let section: CGFloat = 14
        static let contentInset: CGFloat = 4
    }

    enum Font {
        static let largeTitle = NSFont.systemFont(ofSize: 26, weight: .semibold)
        static let title = NSFont.systemFont(ofSize: 20, weight: .semibold)
        static let headline = NSFont.systemFont(ofSize: 14, weight: .semibold)
        static let body = NSFont.systemFont(ofSize: 13)
        static let footnote = NSFont.systemFont(ofSize: 12)
        static let status = NSFont.systemFont(ofSize: 14, weight: .medium)
    }

    enum Color {
        static let title = NSColor.labelColor
        static let body = NSColor.secondaryLabelColor

        /// Deep claret — jediná committed brand barva. Logo, akcenty, brand emphasis.
        static let accent = NSColor(srgbRed: 0.42, green: 0.13, blue: 0.16, alpha: 1)
        static let accentSoft = NSColor(srgbRed: 0.42, green: 0.13, blue: 0.16, alpha: 0.10)

        /// Cream "paper" — foreground na accent površích (logo glyph, případně reverse text).
        static let brandPaper = NSColor(srgbRed: 0.97, green: 0.94, blue: 0.91, alpha: 1)

        /// Warm-tinted window background, auto adapt pro light/dark.
        static let surface: NSColor = {
            NSColor(name: "DictatorSurface", dynamicProvider: { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark
                    ? NSColor(srgbRed: 0.12, green: 0.10, blue: 0.10, alpha: 1)
                    : NSColor(srgbRed: 0.99, green: 0.98, blue: 0.97, alpha: 1)
            })
        }()

        /// Card background — paper-cream tint v light mode, warm-ink v dark mode.
        /// Subtly tmavší/světlejší než surface, aby karty měly vlastní vrstvu, ale zůstaly v rodině.
        static let panel: NSColor = {
            NSColor(name: "DictatorPanel", dynamicProvider: { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark
                    ? NSColor(srgbRed: 0.17, green: 0.13, blue: 0.13, alpha: 1)
                    : NSColor(srgbRed: 0.94, green: 0.91, blue: 0.88, alpha: 1)
            })
        }()

        /// Warm-tinted separator — zaznamenává hranice karet bez „system gray" disonance.
        static let separator: NSColor = {
            NSColor(name: "DictatorSeparator", dynamicProvider: { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark
                    ? NSColor(srgbRed: 0.28, green: 0.22, blue: 0.22, alpha: 1)
                    : NSColor(srgbRed: 0.85, green: 0.79, blue: 0.76, alpha: 1)
            })
        }()

        static let success = NSColor.systemGreen
        static let warning = NSColor.systemOrange
        /// Mírně světlejší claret než accent — error/danger stavy zůstávají v bordó rodině.
        static let danger = NSColor(srgbRed: 0.62, green: 0.18, blue: 0.20, alpha: 1)
        /// Saturated warm red pro recording dot — alarm signál, ale teplejší tón než systemRed.
        static let recording = NSColor(srgbRed: 0.82, green: 0.28, blue: 0.22, alpha: 1)
    }

    static func label(_ text: String, font: NSFont, color: NSColor, lines: Int = 1) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = .natural
        field.maximumNumberOfLines = lines == 0 ? 0 : lines
        field.lineBreakMode = .byWordWrapping
        field.isSelectable = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    static func button(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        return button
    }

    static func configureUtilityWindow(_ window: NSWindow, title: String) {
        window.title = title
        window.center()
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = Color.surface
    }

    /// Hlavní a nastavovací okna — normální úroveň, musí vyjet před systémovými dialogy.
    static func configureMainWindow(_ window: NSWindow, title: String) {
        window.title = title
        window.center()
        window.level = .normal
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        window.backgroundColor = Color.surface
        window.minSize = NSSize(width: 520, height: 480)
        window.contentMinSize = NSSize(width: 520, height: 480)
    }

    static func pinScrollViewToWindow(_ scrollView: NSScrollView, in contentView: NSView) {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    static func primaryButton(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = button(title, target: target, action: action)
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        return button
    }

    static func secondaryButton(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = button(title, target: target, action: action)
        button.controlSize = .regular
        return button
    }

    static func badge(_ text: String, color: NSColor) -> NSTextField {
        let field = label(text, font: Font.footnote, color: color)
        field.setContentHuggingPriority(.required, for: .horizontal)
        return field
    }

    static func card(_ views: [NSView]) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.backgroundColor = Color.panel.cgColor
        container.layer?.borderColor = Color.separator.cgColor
        container.layer?.borderWidth = 1
        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Spacing.row
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Spacing.cardPadding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Spacing.cardPadding),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: Spacing.cardPadding),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Spacing.cardPadding)
        ])

        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        return container
    }
}
