import Cocoa

@MainActor
final class TranscriptionPanelView: NSView {
    /// Called with the text of the row whose "vložit" button was tapped.
    /// (Historically only the newest, now any row — keeps the same signature.)
    var onInsert: ((String) -> Void)?

    private let placeholderLabel = AppTheme.label(
        "Zatím nic — nadiktuj podržením Option (⌥) v libovolné aplikaci.",
        font: AppTheme.Font.body,
        color: AppTheme.Color.body,
        lines: 0
    )

    private let scrollView = NSScrollView()
    private let entriesStack = NSStackView()
    private var rowViews: [HistoryRowView] = []

    private static let historyDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "d. M., HH:mm"
        return f
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    func setHistory(_ entries: [TranscriptionHistoryEntry]) {
        // Wipe existing rows.
        for row in rowViews { row.removeFromSuperview() }
        rowViews.removeAll()
        // Remove any leftover separators added between rows.
        for view in entriesStack.arrangedSubviews {
            entriesStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard !entries.isEmpty else {
            placeholderLabel.isHidden = false
            return
        }

        placeholderLabel.isHidden = true

        for (idx, entry) in entries.enumerated() {
            let row = HistoryRowView(
                entry: entry,
                timestamp: Self.historyDateFormatter.string(from: entry.recordedAt),
                onCopy: { [weak self] text in self?.copyToPasteboard(text) },
                onInsert: { [weak self] text in self?.onInsert?(text) }
            )
            rowViews.append(row)
            entriesStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: entriesStack.widthAnchor).isActive = true

            if idx < entries.count - 1 {
                let sep = Self.makeSeparator()
                entriesStack.addArrangedSubview(sep)
                sep.widthAnchor.constraint(equalTo: entriesStack.widthAnchor).isActive = true
            }
        }
    }

    // MARK: - Layout

    private func buildLayout() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = AppTheme.Color.panel.cgColor
        layer?.borderColor = AppTheme.Color.separator.cgColor
        layer?.borderWidth = 1

        let titleLabel = AppTheme.label("Historie přepisů", font: AppTheme.Font.headline, color: AppTheme.Color.title)
        let helperLabel = AppTheme.label(
            "Nejnovější nahoře. U každého přepisu zkopíruj text nebo ho vlož do aktivního pole.",
            font: AppTheme.Font.footnote,
            color: AppTheme.Color.body,
            lines: 0
        )

        entriesStack.orientation = .vertical
        entriesStack.alignment = .leading
        entriesStack.spacing = AppTheme.Spacing.section
        entriesStack.translatesAutoresizingMaskIntoConstraints = false
        entriesStack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = entriesStack
        scrollView.contentView.postsBoundsChangedNotifications = false
        if let clip = scrollView.contentView as NSClipView? {
            clip.drawsBackground = false
        }

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [titleLabel, helperLabel, scrollView])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = AppTheme.Spacing.section
        content.translatesAutoresizingMaskIntoConstraints = false
        content.setCustomSpacing(AppTheme.Spacing.tight, after: titleLabel)
        content.setCustomSpacing(AppTheme.Spacing.row, after: helperLabel)

        addSubview(content)
        // Placeholder lives over the scroll view (visible only when there are no entries).
        addSubview(placeholderLabel)

        let pad = AppTheme.Spacing.cardPadding
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            content.topAnchor.constraint(equalTo: topAnchor, constant: pad),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad),

            titleLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
            helperLabel.widthAnchor.constraint(equalTo: content.widthAnchor),

            scrollView.widthAnchor.constraint(equalTo: content.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),

            entriesStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            placeholderLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -8),
            placeholderLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 8)
        ])
    }

    // MARK: - Helpers

    private func copyToPasteboard(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
    }

    private static func makeSeparator() -> NSView {
        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = AppTheme.Color.separator.cgColor
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }
}

// MARK: - Per-entry row

@MainActor
private final class HistoryRowView: NSView {
    private let text: String
    private let copyButton: NSButton
    private let insertButton: NSButton
    private var copyRevertTimer: Timer?

    private static let copyDefaultTitle = "Zkopírovat"
    private static let copyDoneTitle = "Zkopírováno"

    init(
        entry: TranscriptionHistoryEntry,
        timestamp: String,
        onCopy: @escaping (String) -> Void,
        onInsert: @escaping (String) -> Void
    ) {
        self.text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)

        self.copyButton = HistoryRowView.makeSmallButton(
            title: Self.copyDefaultTitle,
            symbol: "doc.on.doc",
            tint: AppTheme.Color.body
        )
        self.insertButton = HistoryRowView.makeSmallButton(
            title: "Vložit",
            symbol: "text.insert",
            tint: AppTheme.Color.accent
        )

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let timestampLabel = AppTheme.label(timestamp, font: AppTheme.Font.footnote, color: AppTheme.Color.body)
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false

        let bodyLabel = AppTheme.label(text, font: AppTheme.Font.body, color: AppTheme.Color.title, lines: 0)
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.isSelectable = true

        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        insertButton.target = self
        insertButton.action = #selector(insertTapped)

        self.onCopy = onCopy
        self.onInsert = onInsert

        let actions = NSStackView(views: [copyButton, insertButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = AppTheme.Spacing.row
        actions.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [timestampLabel, bodyLabel, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = AppTheme.Spacing.tight
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(AppTheme.Spacing.intimate, after: bodyLabel)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            timestampLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bodyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        if text.isEmpty {
            copyButton.isEnabled = false
            insertButton.isEnabled = false
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        copyRevertTimer?.invalidate()
    }

    private var onCopy: ((String) -> Void)?
    private var onInsert: ((String) -> Void)?

    @objc private func copyTapped() {
        onCopy?(text)
        copyButton.title = Self.copyDoneTitle
        copyRevertTimer?.invalidate()
        copyRevertTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.copyButton.title = Self.copyDefaultTitle
            }
        }
    }

    @objc private func insertTapped() {
        onInsert?(text)
    }

    private static func makeSmallButton(title: String, symbol: String, tint: NSColor) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .roundRect
        button.controlSize = .small
        button.font = AppTheme.Font.footnote
        button.setButtonType(.momentaryPushIn)

        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            button.image = image.withSymbolConfiguration(config)
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = tint
        }
        return button
    }
}
