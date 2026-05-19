import AVFoundation
import Cocoa

enum PermissionCheckState: Equatable {
    case allowed
    case missing
    case needsReview

    var label: String {
        switch self {
        case .allowed: return "Povoleno"
        case .missing: return "Chybí"
        case .needsReview: return "Zkontrolujte"
        }
    }

    var color: NSColor {
        switch self {
        case .allowed: return AppTheme.Color.success
        case .missing: return AppTheme.Color.warning
        case .needsReview: return AppTheme.Color.danger
        }
    }
}

struct PermissionsSnapshot: Equatable {
    let microphone: PermissionCheckState
    let accessibility: PermissionCheckState

    var allGranted: Bool {
        microphone == .allowed && accessibility == .allowed
    }
}

@MainActor
final class PermissionsWindowController: NSWindowController {
    var onPermissionsGranted: (() -> Void)?

    private var checkTimer: Timer?
    private let microphoneBadge = AppTheme.badge("Chybí", color: AppTheme.Color.warning)
    private let accessibilityBadge = AppTheme.badge("Chybí", color: AppTheme.Color.warning)
    private let microphoneButton = AppTheme.secondaryButton("Povolit mikrofon", target: nil, action: nil)
    private let accessibilityButton = AppTheme.secondaryButton("Otevřít Nastavení", target: nil, action: nil)
    private let checkAgainButton = AppTheme.primaryButton("Zkontrolovat znovu", target: nil, action: nil)
    private let revealAppButton = AppTheme.secondaryButton("Ukázat ve Finderu", target: nil, action: nil)
    private let copyLogButton = AppTheme.secondaryButton("Zkopírovat log", target: nil, action: nil)
    private let keyTestStatusLabel = AppTheme.label(
        "Stiskni svou diktovací klávesu — Dictator ukáže, jestli ji vidí.",
        font: AppTheme.Font.body,
        color: AppTheme.Color.body,
        lines: 0
    )
    private var keyTestHintTimer: Timer?
    private let hotkeyPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let vocabularyTextView = NSTextView()
    private let vocabularyStatusLabel = AppTheme.label("", font: AppTheme.Font.footnote, color: AppTheme.Color.body)
    private var vocabularyStatusResetTimer: Timer?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        AppTheme.configureMainWindow(window, title: "Nastavení Dictatoru")

        super.init(window: window)

        buildUI()
        wireActions()
        refreshPermissionState()
        startPolling()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        AppWindowPresenter.present(window)
    }

    override func close() {
        checkTimer?.invalidate()
        checkTimer = nil
        keyTestHintTimer?.invalidate()
        keyTestHintTimer = nil
        super.close()
    }

    func reportKeyEvent(key: HotkeyKey, isDown: Bool) {
        guard isDown else { return }
        keyTestHintTimer?.invalidate()

        let formatter = DateFormatter()
        formatter.timeStyle = .medium

        switch key {
        case .option, .leftOption:
            keyTestStatusLabel.stringValue = "Zachyceno v \(formatter.string(from: Date()))"
            keyTestStatusLabel.textColor = AppTheme.Color.success
        }

        keyTestHintTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resetKeyTestHintIfStale()
            }
        }
    }

    private func resetKeyTestHintIfStale() {
        keyTestStatusLabel.stringValue = "Stiskni svou diktovací klávesu — Dictator ukáže, jestli ji vidí."
        keyTestStatusLabel.textColor = AppTheme.Color.body
    }

    private func buildHotkeyCard() -> NSView {
        hotkeyPicker.removeAllItems()
        hotkeyPicker.addItems(withTitles: HotkeyChoice.allCases.map(\.label))
        let currentIndex = HotkeyChoice.allCases.firstIndex(of: HotkeyPreference.current) ?? 0
        hotkeyPicker.selectItem(at: currentIndex)
        hotkeyPicker.target = self
        hotkeyPicker.action = #selector(hotkeyChoiceChanged(_:))

        let title = AppTheme.label("Klávesa pro diktování", font: AppTheme.Font.headline, color: AppTheme.Color.title)
        let detail = AppTheme.label(
            "Defaultně levý nebo pravý Option (⌥). Pokud používáš pravý Option jako AltGr pro české znaky (@, #, &), zvol jinou klávesu.",
            font: AppTheme.Font.body,
            color: AppTheme.Color.body,
            lines: 0
        )

        return AppTheme.card([title, detail, hotkeyPicker])
    }

    @objc private func hotkeyChoiceChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < HotkeyChoice.allCases.count else { return }
        HotkeyPreference.current = HotkeyChoice.allCases[idx]
        DiagnosticsLogger.log("Hotkey preference changed to \(HotkeyChoice.allCases[idx].rawValue)")
    }

    private func buildVocabularyCard() -> NSView {
        let title = AppTheme.label("Vlastní slovník (volitelné)", font: AppTheme.Font.headline, color: AppTheme.Color.title)
        let detail = AppTheme.label(
            "Whisper se občas netrefí do produktových termínů. Přidej je sem, jeden na řádek. Pro fonetické varianty: MyCompany: my company, maj company",
            font: AppTheme.Font.footnote,
            color: AppTheme.Color.body,
            lines: 0
        )

        vocabularyTextView.isEditable = true
        vocabularyTextView.isSelectable = true
        vocabularyTextView.isAutomaticQuoteSubstitutionEnabled = false
        vocabularyTextView.isAutomaticDashSubstitutionEnabled = false
        vocabularyTextView.isAutomaticTextReplacementEnabled = false
        vocabularyTextView.isAutomaticSpellingCorrectionEnabled = false
        vocabularyTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        vocabularyTextView.textColor = AppTheme.Color.title
        vocabularyTextView.drawsBackground = true
        vocabularyTextView.backgroundColor = AppTheme.Color.surface
        vocabularyTextView.isVerticallyResizable = true
        vocabularyTextView.isHorizontallyResizable = false
        vocabularyTextView.textContainer?.widthTracksTextView = true
        vocabularyTextView.textContainerInset = NSSize(width: 8, height: 8)
        vocabularyTextView.string = VocabularyStore.currentRawText

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .lineBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = vocabularyTextView
        scrollView.heightAnchor.constraint(equalToConstant: 160).isActive = true

        let saveButton = AppTheme.secondaryButton("Uložit slovník", target: self, action: #selector(saveVocabulary))
        saveButton.bezelColor = AppTheme.Color.accent
        let resetButton = AppTheme.secondaryButton("Obnovit výchozí", target: self, action: #selector(resetVocabulary))
        let buttonSpacer = NSView()
        buttonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [saveButton, resetButton, buttonSpacer, vocabularyStatusLabel])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = AppTheme.Spacing.row

        return AppTheme.card([title, detail, scrollView, buttons])
    }

    @objc private func saveVocabulary() {
        VocabularyStore.currentRawText = vocabularyTextView.string
        flashVocabularyStatus("Uloženo. Whisper si načítá nový slovník.", color: AppTheme.Color.success)
    }

    @objc private func resetVocabulary() {
        VocabularyStore.resetToDefault()
        vocabularyTextView.string = VocabularyStore.currentRawText
        flashVocabularyStatus("Slovník vrácený na výchozí.", color: AppTheme.Color.body)
    }

    private func flashVocabularyStatus(_ message: String, color: NSColor) {
        vocabularyStatusLabel.stringValue = message
        vocabularyStatusLabel.textColor = color
        vocabularyStatusResetTimer?.invalidate()
        vocabularyStatusResetTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.vocabularyStatusLabel.stringValue = ""
            }
        }
    }

    private func buildUI() {
        let logo = AppLogoView()
        logo.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 64),
            logo.heightAnchor.constraint(equalToConstant: 64)
        ])

        let title = AppTheme.label(
            "Dokončete nastavení",
            font: AppTheme.Font.title,
            color: AppTheme.Color.title
        )
        let subtitle = AppTheme.label(
            "Povolte dvě lokální oprávnění. Jakmile budou hotová, Dictator bude připravený k diktování.",
            font: AppTheme.Font.body,
            color: AppTheme.Color.body,
            lines: 0
        )

        let headerText = NSStackView(views: [title, subtitle])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = AppTheme.Spacing.tight

        let header = NSStackView(views: [logo, headerText])
        header.orientation = .horizontal
        header.alignment = .top
        header.spacing = AppTheme.Spacing.stack
        header.translatesAutoresizingMaskIntoConstraints = false
        headerText.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let microphoneRow = permissionRow(
            number: "1",
            title: "Mikrofon",
            detail: "Nahrává jen ve chvíli, kdy držíte Option (⌥).",
            badge: microphoneBadge,
            button: microphoneButton
        )

        let accessibilityRow = permissionRow(
            number: "2",
            title: "Zpřístupnění",
            detail: "V Nastavení musí být povolená přesně tato kopie Dictatoru. Cesta: Soukromí a zabezpečení → Zpřístupnění (anglicky Accessibility).",
            badge: accessibilityBadge,
            button: accessibilityButton
        )

        let hotkeyCard = buildHotkeyCard()
        let vocabularyCard = buildVocabularyCard()

        let keyTestCard = AppTheme.card([
            AppTheme.label("Otestuj diktovací klávesu", font: AppTheme.Font.headline, color: AppTheme.Color.title),
            keyTestStatusLabel
        ])

        let helper = AppTheme.label(
            "Pokud už je Dictator v Nastavení povolený a stále svítí problém, odeberte starou položku Dictatoru a přidejte aktuální aplikaci z Finderu.",
            font: AppTheme.Font.footnote,
            color: AppTheme.Color.body,
            lines: 0
        )

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footerButtons = NSStackView(views: [checkAgainButton, footerSpacer, revealAppButton, copyLogButton])
        footerButtons.orientation = .horizontal
        footerButtons.alignment = .centerY
        footerButtons.spacing = AppTheme.Spacing.row

        let scrollView = NSScrollView()
        let contentView = NSView()
        window?.contentView = contentView
        AppTheme.pinScrollViewToWindow(scrollView, in: contentView)

        let contentStack = ScrollContentLayout.install(
            in: scrollView,
            arrangedSubviews: [
                header,
                microphoneRow,
                accessibilityRow,
                hotkeyCard,
                vocabularyCard,
                keyTestCard,
                footerButtons,
                helper
            ]
        )
        contentStack.setCustomSpacing(AppTheme.Spacing.hero, after: header)
        contentStack.setCustomSpacing(AppTheme.Spacing.intimate, after: footerButtons)
    }

    /// Numbered checklist row: large claret digit on the left, content stack on the right.
    /// Replaces a card so two permissions don't feel like four UI primitives.
    private func permissionRow(number: String, title: String, detail: String, badge: NSTextField, button: NSButton) -> NSView {
        let numberLabel = NSTextField(labelWithString: number)
        numberLabel.font = NSFont.systemFont(ofSize: 32, weight: .semibold)
        numberLabel.textColor = AppTheme.Color.accent
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = AppTheme.label(title, font: AppTheme.Font.headline, color: AppTheme.Color.title)
        let detailLabel = AppTheme.label(detail, font: AppTheme.Font.body, color: AppTheme.Color.body, lines: 0)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let titleRow = NSStackView(views: [titleLabel, spacer, badge])
        titleRow.orientation = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = AppTheme.Spacing.row
        badge.setContentHuggingPriority(.required, for: .horizontal)

        let content = NSStackView(views: [titleRow, detailLabel, button])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = AppTheme.Spacing.tight
        content.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(numberLabel)
        row.addSubview(content)

        NSLayoutConstraint.activate([
            numberLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 4),
            numberLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: -6),
            numberLabel.widthAnchor.constraint(equalToConstant: 36),

            content.leadingAnchor.constraint(equalTo: numberLabel.trailingAnchor, constant: AppTheme.Spacing.row),
            content.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            content.topAnchor.constraint(equalTo: row.topAnchor),
            content.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])

        return row
    }

    private func wireActions() {
        microphoneButton.target = self
        microphoneButton.action = #selector(requestMicrophone)
        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibilitySettings)
        checkAgainButton.target = self
        checkAgainButton.action = #selector(checkAgain)
        revealAppButton.target = self
        revealAppButton.action = #selector(revealCurrentApp)
        copyLogButton.target = self
        copyLogButton.action = #selector(copyDiagnosticsLog)
    }

    @objc private func copyDiagnosticsLog() {
        DiagnosticsLogger.copyTailToPasteboard(50)
        keyTestStatusLabel.stringValue = "Posledních 50 řádků logu je ve schránce."
        keyTestStatusLabel.textColor = AppTheme.Color.success
        keyTestHintTimer?.invalidate()
        keyTestHintTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resetKeyTestHintIfStale()
            }
        }
    }

    private func startPolling() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionState()
                guard Self.currentSnapshot.allGranted else { return }
                self?.close()
                self?.onPermissionsGranted?()
            }
        }
    }

    private func refreshPermissionState() {
        let snapshot = Self.currentSnapshot
        DiagnosticsLogger.log("Permissions refreshed. microphone=\(snapshot.microphone.label), accessibility=\(snapshot.accessibility.label)")

        microphoneBadge.stringValue = snapshot.microphone.label
        microphoneBadge.textColor = snapshot.microphone.color
        microphoneButton.isHidden = snapshot.microphone == .allowed

        accessibilityBadge.stringValue = snapshot.accessibility.label
        accessibilityBadge.textColor = snapshot.accessibility.color
        accessibilityButton.isHidden = snapshot.accessibility == .allowed
    }

    @objc private func requestMicrophone() {
        DiagnosticsLogger.log("Microphone permission requested")
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissionState() }
        }
        openMicrophoneSettings()
    }

    @objc private func openAccessibilitySettings() {
        DiagnosticsLogger.log("Accessibility settings opened")
        AppWindowPresenter.activateApp()
        AppWindowPresenter.present(window)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            _ = Self.isAccessibilityGranted(prompt: true)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            self.refreshPermissionState()
        }
    }

    @objc private func checkAgain() {
        DiagnosticsLogger.log("Manual permission recheck requested")
        refreshPermissionState()
        if Self.currentSnapshot.allGranted {
            close()
            onPermissionsGranted?()
        }
    }

    @objc private func revealCurrentApp() {
        DiagnosticsLogger.log("Reveal current app requested. Bundle path: \(Bundle.main.bundleURL.path)")
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    static var isMicrophoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var currentSnapshot: PermissionsSnapshot {
        PermissionsSnapshot(
            microphone: microphoneState,
            accessibility: isAccessibilityGranted(prompt: false) ? .allowed : .needsReview
        )
    }

    private static var microphoneState: PermissionCheckState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .allowed
        case .notDetermined:
            return .missing
        case .denied, .restricted:
            return .needsReview
        @unknown default:
            return .needsReview
        }
    }

    static func isAccessibilityGranted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
