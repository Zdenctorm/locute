import Cocoa

@MainActor
final class LearnedTermsWindowController: NSWindowController {
    private let contentView = LearnedTermsView()
    private var learnedObserver: NSObjectProtocol?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        AppTheme.configureMainWindow(window, title: "Co jsem se naučil")

        super.init(window: window)
        window.contentView = contentView
        contentView.onEntriesChanged = { [weak self] in self?.reloadList() }
        reloadList()

        learnedObserver = NotificationCenter.default.addObserver(
            forName: .dictatorLearnedTermsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadList()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let learnedObserver {
            NotificationCenter.default.removeObserver(learnedObserver)
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        reloadList()
        AppWindowPresenter.present(window)
    }

    private func reloadList() {
        contentView.setEntries(LearningEngine.shared.learnedEntries)
    }
}

// MARK: - Content

@MainActor
final class LearnedTermsView: NSView {
    var onEntriesChanged: (() -> Void)?

    private let listStack = NSStackView()
    private let emptyLabel = AppTheme.label(
        "Zatím nic — \(AppBrand.displayName) se učí z oprav v historii nebo když stejnou větu řekneš znovu.",
        font: AppTheme.Font.body,
        color: AppTheme.Color.body,
        lines: 0
    )
    private let advancedDisclosure = NSButton(title: "Pokročilé: ručně přidat termín", target: nil, action: nil)
    private let advancedPanel = NSView()
    private let canonicalField = NSTextField()
    private let variantRowsStack = NSStackView()
    private var variantFields: [NSTextField] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        AppTheme.applyPanelChrome(to: advancedPanel, cornerRadius: 12)
    }

    func setEntries(_ entries: [LearnedEntry]) {
        for view in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let sorted = entries.sorted { $0.lastConfirmedAt > $1.lastConfirmedAt }
        emptyLabel.isHidden = !sorted.isEmpty

        for entry in sorted {
            listStack.addArrangedSubview(makeEntryRow(entry))
        }
    }

    private func buildLayout() {
        translatesAutoresizingMaskIntoConstraints = false

        let intro = AppTheme.label(
            "Termíny, které \(AppBrand.displayName) používá při přepisu. Můžeš je smazat nebo přidat ručně.",
            font: AppTheme.Font.body,
            color: AppTheme.Color.body,
            lines: 0
        )

        let privacy = AppTheme.label(
            "Soukromí: přepisy a naučené termíny zůstávají jen na tomto Macu. Zvuk z posledních nahrávek se drží na disku maximálně 1 hodinu.",
            font: AppTheme.Font.footnote,
            color: AppTheme.Color.body,
            lines: 0
        )

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = AppTheme.Spacing.row

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        buildAdvancedPanel()

        advancedDisclosure.setButtonType(.toggle)
        advancedDisclosure.bezelStyle = .inline
        advancedDisclosure.font = AppTheme.Font.footnote
        advancedDisclosure.target = self
        advancedDisclosure.action = #selector(toggleAdvanced)
        advancedPanel.isHidden = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let listContainer = NSStackView(views: [emptyLabel, listStack])
        listContainer.orientation = .vertical
        listContainer.alignment = .leading
        listContainer.spacing = AppTheme.Spacing.section
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = listContainer

        let root = NSStackView(views: [intro, scrollView, privacy, advancedDisclosure, advancedPanel])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = AppTheme.Spacing.section
        root.translatesAutoresizingMaskIntoConstraints = false
        root.edgeInsets = NSEdgeInsets(
            top: AppTheme.Spacing.windowPadding,
            left: AppTheme.Spacing.windowPadding,
            bottom: AppTheme.Spacing.windowPadding,
            right: AppTheme.Spacing.windowPadding
        )

        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),

            intro.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -AppTheme.Spacing.windowPadding * 2),
            privacy.widthAnchor.constraint(equalTo: intro.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: intro.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            listContainer.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            advancedPanel.widthAnchor.constraint(equalTo: intro.widthAnchor)
        ])
    }

    private func buildAdvancedPanel() {
        advancedPanel.translatesAutoresizingMaskIntoConstraints = false
        advancedPanel.wantsLayer = true
        AppTheme.applyPanelChrome(to: advancedPanel, cornerRadius: 12)

        let canonicalLabel = AppTheme.label("Kanonický tvar", font: AppTheme.Font.footnote, color: AppTheme.Color.body)
        canonicalField.placeholderString = "např. Anycoin"
        canonicalField.font = AppTheme.Font.body
        canonicalField.translatesAutoresizingMaskIntoConstraints = false

        let variantsLabel = AppTheme.label("Varianty (co Whisper často řekne špatně)", font: AppTheme.Font.footnote, color: AppTheme.Color.body)
        variantRowsStack.orientation = .vertical
        variantRowsStack.alignment = .leading
        variantRowsStack.spacing = AppTheme.Spacing.tight

        addVariantRow(prefill: "")

        let addVariantButton = AppTheme.secondaryButton("+ Přidat variantu", target: self, action: #selector(addVariantRowTapped))
        let saveButton = AppTheme.primaryButton("Uložit termín", target: self, action: #selector(saveManualTerm))

        let inner = NSStackView(views: [
            canonicalLabel, canonicalField, variantsLabel, variantRowsStack, addVariantButton, saveButton
        ])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = AppTheme.Spacing.tight
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        advancedPanel.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: advancedPanel.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: advancedPanel.trailingAnchor),
            inner.topAnchor.constraint(equalTo: advancedPanel.topAnchor),
            inner.bottomAnchor.constraint(equalTo: advancedPanel.bottomAnchor),
            canonicalField.widthAnchor.constraint(equalTo: inner.widthAnchor, constant: -24),
            variantRowsStack.widthAnchor.constraint(equalTo: canonicalField.widthAnchor)
        ])
    }

    private func makeEntryRow(_ entry: LearnedEntry) -> NSView {
        let title = entry.canonical
        let usage = entry.usageCount
        let usageText = usage == 1 ? "1× použito" : "\(usage)× použito"
        let pending = entry.confirmationCount < 2
        let statusSuffix = pending ? " · čeká na potvrzení" : ""

        let variantTexts = entry.variants.map(\.text)
        let subtitle = variantTexts.isEmpty
            ? usageText + statusSuffix
            : "\(usageText) · varianty: \(variantTexts.joined(separator: ", "))"

        let titleLabel = AppTheme.label(title, font: AppTheme.Font.headline, color: AppTheme.Color.title)
        let subtitleLabel = AppTheme.label(subtitle, font: AppTheme.Font.footnote, color: AppTheme.Color.body, lines: 0)

        let deleteButton = NSButton(title: "✕", target: nil, action: nil)
        deleteButton.bezelStyle = .inline
        deleteButton.font = AppTheme.Font.body
        deleteButton.toolTip = "Smazat termín"
        AccessibilitySupport.configure(deleteButton, label: "Smazat termín \(title)")
        deleteButton.target = self
        deleteButton.action = #selector(deleteEntry(_:))
        deleteButton.identifier = NSUserInterfaceItemIdentifier(entry.canonical)

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [textStack, spacer, deleteButton])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = AppTheme.Spacing.row
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 440).isActive = true

        return AppTheme.card([row])
    }

    @objc private func deleteEntry(_ sender: NSButton) {
        guard let canonical = sender.identifier?.rawValue else { return }
        let alert = NSAlert()
        alert.messageText = "Smazat „\(canonical)“?"
        alert.informativeText = "\(AppBrand.displayName) přestane tento termín upravovat v přepisech."
        alert.addButton(withTitle: "Smazat")
        alert.addButton(withTitle: "Zrušit")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        LearningEngine.shared.removeEntry(canonical: canonical)
        onEntriesChanged?()
    }

    @objc private func toggleAdvanced(_ sender: NSButton) {
        advancedPanel.isHidden = sender.state != .on
    }

    @objc private func addVariantRowTapped() {
        addVariantRow(prefill: "")
    }

    private func addVariantRow(prefill: String) {
        let field = NSTextField()
        field.placeholderString = "fonetická varianta"
        field.stringValue = prefill
        field.font = AppTheme.Font.body
        field.translatesAutoresizingMaskIntoConstraints = false

        let remove = NSButton(title: "−", target: self, action: #selector(removeVariantRow(_:)))
        remove.bezelStyle = .inline
        remove.tag = variantFields.count

        let row = NSStackView(views: [field, remove])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = AppTheme.Spacing.tight
        row.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        variantFields.append(field)
        variantRowsStack.addArrangedSubview(row)
    }

    @objc private func removeVariantRow(_ sender: NSButton) {
        guard variantFields.count > 1 else { return }
        let idx = sender.tag
        guard idx >= 0, idx < variantRowsStack.arrangedSubviews.count else { return }
        let row = variantRowsStack.arrangedSubviews[idx]
        variantRowsStack.removeArrangedSubview(row)
        row.removeFromSuperview()
        variantFields.remove(at: idx)
        reindexVariantRemoveButtons()
    }

    private func reindexVariantRemoveButtons() {
        for (idx, row) in variantRowsStack.arrangedSubviews.enumerated() {
            guard let stack = row as? NSStackView,
                  let remove = stack.arrangedSubviews.last as? NSButton else { continue }
            remove.tag = idx
        }
    }

    @objc private func saveManualTerm() {
        let canonical = canonicalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty else { return }

        let variants = variantFields
            .map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !variants.isEmpty else { return }

        for variant in variants {
            LearningEngine.shared.observeUserCorrection(
                variant: variant,
                canonical: canonical,
                source: .userTypedInDict
            )
        }

        canonicalField.stringValue = ""
        for field in variantFields { field.stringValue = "" }
        onEntriesChanged?()
    }
}
