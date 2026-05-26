import Cocoa

@MainActor
final class TranscriptionPanelView: NSView {
    static let wordMarkupLegend = """
    Nejnovější nahoře. Klikni na podtržené slovo pro opravu. \
    Plné zelené podtržení: už opravené slovo. Tečkované oranžové: nízká jistota přepisu. \
    Šedé plné: střední jistota. U každého přepisu můžeš text zkopírovat nebo vložit do aktivního pole.
    """

    /// Called with the text of the row whose "vložit" button was tapped.
    var onInsert: ((String) -> Void)?

    private let placeholderLabel = AppTheme.label(
        "Zatím nic — podrž Option (⌥) a mluv. Přepisy se objeví tady; do jiné aplikace je vložíš tlačítkem „Vložit“.",
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
        for row in rowViews { row.removeFromSuperview() }
        rowViews.removeAll()
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
        AccessibilitySupport.configure(
            self,
            label: "Historie přepisů",
            help: Self.wordMarkupLegend,
            role: .group
        )

        let titleLabel = AppTheme.label("Historie přepisů", font: AppTheme.Font.headline, color: AppTheme.Color.title)
        let helperLabel = AppTheme.label(
            Self.wordMarkupLegend,
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

// MARK: - Word link helpers

enum DictatorWordLink {
    static let scheme = "dictator"

    static func url(entryID: UUID, wordIndex: Int) -> URL? {
        URL(string: "\(scheme)://word/\(entryID.uuidString)/\(wordIndex)")
    }

    static func parse(_ url: URL) -> (entryID: UUID, wordIndex: Int)? {
        guard url.scheme == scheme, url.host == "word" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2,
              let entryID = UUID(uuidString: parts[0]),
              let wordIndex = Int(parts[1]) else { return nil }
        return (entryID, wordIndex)
    }
}

// MARK: - Per-entry row

@MainActor
private final class HistoryRowView: NSView, NSTextViewDelegate {
    private let entry: TranscriptionHistoryEntry
    private let text: String
    private let words: [WordToken]
    private let bodyTextView: NSTextView
    private var bodyHeightConstraint: NSLayoutConstraint?
    private let copyButton: NSButton
    private let insertButton: NSButton
    private var copyRevertTimer: Timer?
    private var lastMeasuredTextWidth: CGFloat = 0

    private static let copyDefaultTitle = "Zkopírovat"
    private static let copyDoneTitle = "Zkopírováno"

    init(
        entry: TranscriptionHistoryEntry,
        timestamp: String,
        onCopy: @escaping (String) -> Void,
        onInsert: @escaping (String) -> Void
    ) {
        self.entry = entry
        self.text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.words = entry.words.isEmpty ? Self.fallbackWords(from: entry.text) : entry.words

        self.bodyTextView = NSTextView()
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

        configureBodyTextView()
        bodyTextView.textStorage?.setAttributedString(Self.buildAttributedBody(entry: entry, words: words))
        let spokenText = text.isEmpty ? "Prázdný přepis" : text
        bodyTextView.setAccessibilityLabel(spokenText)
        bodyTextView.setAccessibilityHelp(TranscriptionPanelView.wordMarkupLegend)

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

        let stack = NSStackView(views: [timestampLabel, bodyTextView, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = AppTheme.Spacing.tight
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(AppTheme.Spacing.intimate, after: bodyTextView)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            timestampLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bodyTextView.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        updateBodyHeight()

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

    private func configureBodyTextView() {
        bodyTextView.isEditable = false
        bodyTextView.isSelectable = true
        bodyTextView.drawsBackground = false
        bodyTextView.backgroundColor = .clear
        bodyTextView.textContainerInset = NSSize(width: 0, height: 2)
        bodyTextView.isVerticallyResizable = true
        bodyTextView.isHorizontallyResizable = false
        bodyTextView.textContainer?.widthTracksTextView = true
        bodyTextView.textContainer?.lineFragmentPadding = 0
        bodyTextView.delegate = self
        bodyTextView.linkTextAttributes = [
            .foregroundColor: AppTheme.Color.title
        ]
        bodyTextView.translatesAutoresizingMaskIntoConstraints = false
        bodyHeightConstraint = bodyTextView.heightAnchor.constraint(equalToConstant: 24)
        bodyHeightConstraint?.isActive = true
    }

    private func updateBodyHeight() {
        guard bounds.width > 0 else { return }
        bodyTextView.layoutSubtreeIfNeeded()
        guard let layoutManager = bodyTextView.layoutManager,
              let textContainer = bodyTextView.textContainer else { return }
        let targetWidth = max(bodyTextView.bounds.width, 1)
        if abs(textContainer.containerSize.width - targetWidth) > 0.5 {
            textContainer.containerSize = NSSize(width: targetWidth, height: .greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let inset = bodyTextView.textContainerInset.height * 2
        bodyHeightConstraint?.constant = max(used.height + inset, 20)
    }

    override func layout() {
        super.layout()
        let currentWidth = bodyTextView.bounds.width
        guard currentWidth > 0 else { return }
        if abs(currentWidth - lastMeasuredTextWidth) > 0.5 {
            lastMeasuredTextWidth = currentWidth
            updateBodyHeight()
        }
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL,
              let parsed = DictatorWordLink.parse(url),
              parsed.entryID == entry.id,
              parsed.wordIndex >= 0,
              parsed.wordIndex < words.count else { return false }

        let word = words[parsed.wordIndex]
        let glyphRange = layoutManagerGlyphRange(for: charIndex, in: textView)
        let rect = textView.firstRect(forCharacterRange: glyphRange, actualRange: nil)
        let positioningRect = textView.convert(rect, to: textView)
        WordCorrectionPopoverController.shared.present(
            relativeTo: positioningRect,
            of: textView,
            word: word
        )
        return true
    }

    private func layoutManagerGlyphRange(for charIndex: Int, in textView: NSTextView) -> NSRange {
        guard let layoutManager = textView.layoutManager else { return NSRange(location: charIndex, length: 1) }
        var actualRange = NSRange()
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: &actualRange)
        if glyphRange.length > 0 { return glyphRange }
        return NSRange(location: glyphIndex, length: 1)
    }

    @objc private func copyTapped() {
        onCopy?(text)
        copyButton.title = Self.copyDoneTitle
        copyRevertTimer?.invalidate()
        copyRevertTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.copyButton.title = Self.copyDefaultTitle
            }
        }
    }

    @objc private func insertTapped() {
        onInsert?(text)
    }

    private static func fallbackWords(from text: String) -> [WordToken] {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .map { piece -> WordToken in
                let trimmed = String(piece).trimmingCharacters(in: .punctuationCharacters)
                return WordToken(text: trimmed, confidence: 1.0)
            }
            .filter { !$0.text.isEmpty }
    }

    private static func buildAttributedBody(entry: TranscriptionHistoryEntry, words: [WordToken]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, word) in words.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: " ", attributes: baseAttributes()))
            }
            var attrs = baseAttributes()

            let markupHelp = AccessibilitySupport.wordMarkupHelp(
                confidence: Double(word.confidence),
                original: word.originalText
            )

            if let original = word.originalText {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[.underlineColor] = AppTheme.Color.success
                attrs[.toolTip] = markupHelp.isEmpty
                    ? "Z „\(original)“ → „\(word.text)“"
                    : "\(markupHelp) Z „\(original)“ → „\(word.text)“"
            } else if word.confidence < 0.65 {
                attrs[.underlineStyle] = NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue
                attrs[.underlineColor] = AppTheme.Color.warning
                if let url = DictatorWordLink.url(entryID: entry.id, wordIndex: index) {
                    attrs[.link] = url
                }
                if !markupHelp.isEmpty {
                    attrs[.toolTip] = markupHelp
                }
            } else if word.confidence < 0.85 {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[.underlineColor] = NSColor.secondaryLabelColor
                if let url = DictatorWordLink.url(entryID: entry.id, wordIndex: index) {
                    attrs[.link] = url
                }
                if !markupHelp.isEmpty {
                    attrs[.toolTip] = markupHelp
                }
            }

            result.append(NSAttributedString(string: word.text, attributes: attrs))
        }
        return result
    }

    private static func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: AppTheme.Font.body,
            .foregroundColor: AppTheme.Color.title
        ]
    }

    private static func makeSmallButton(title: String, symbol: String, tint: NSColor) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .roundRect
        button.controlSize = .small
        button.font = AppTheme.Font.footnote
        button.setButtonType(.momentaryPushIn)

        AccessibilitySupport.configure(button, label: title)

        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            button.image = image.withSymbolConfiguration(config)
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = tint
        }
        return button
    }
}
