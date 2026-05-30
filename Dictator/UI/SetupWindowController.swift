import AVFoundation
import Cocoa

/// Průvodce nastavením — pouze oprávnění a test diktovací klávesy. Po udělení všech oprávnění se zavře.
@MainActor
final class SetupWindowController: NSWindowController {
    var onPermissionsGranted: (() -> Void)?

    private var checkTimer: Timer?
    private var lastLoggedSnapshot: PermissionsSnapshot?
    private var hadAllPermissionsWhenOpened = false
    private var didRequestAccessibilityPromptThisSession = false
    private let bundlePathLabel = AppTheme.label(
        "",
        font: AppTheme.Font.footnote,
        color: AppTheme.Color.body,
        lines: 0
    )
    private let microphoneBadge = AppTheme.badge("Chybí", color: AppTheme.Color.warning)
    private let accessibilityBadge = AppTheme.badge("Chybí", color: AppTheme.Color.warning)
    private let microphoneButton = AppTheme.secondaryButton("Povolit mikrofon", target: nil, action: nil)
    private let accessibilityButton = AppTheme.secondaryButton(
        "Přidat do Zpřístupnění…",
        target: nil,
        action: nil
    )
    private let inputMonitoringBadge = AppTheme.badge("Chybí", color: AppTheme.Color.warning)
    private let inputMonitoringButton = AppTheme.secondaryButton(
        "Povolit monitorování vstupu…",
        target: nil,
        action: nil
    )
    private let checkAgainButton = AppTheme.primaryButton("Zkontrolovat znovu", target: nil, action: nil)
    private let revealAppButton = AppTheme.secondaryButton("Ukázat ve Finderu", target: nil, action: nil)
    private let copyLogButton = AppTheme.secondaryButton("Zkopírovat log", target: nil, action: nil)
    private let keyTestStatusLabel = AppTheme.label(
        "Stiskni svou diktovací klávesu — \(AppBrand.displayName) ukáže, jestli ji vidí.",
        font: AppTheme.Font.body,
        color: AppTheme.Color.body,
        lines: 0
    )
    private var keyTestHintTimer: Timer?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        AppTheme.configureMainWindow(window, title: "Průvodce nastavením")

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
        hadAllPermissionsWhenOpened = PermissionsSnapshotProvider.current.allGranted
        AppWindowPresenter.activateApp()
        AppWindowPresenter.present(window)
        bundlePathLabel.stringValue = "Aktuální kopie: \(Bundle.main.bundleURL.path)"
        requestAccessibilityPromptIfNeeded()
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
        keyTestStatusLabel.stringValue =
            "Zachyceno (\(HotkeyPreference.current.hintLabel)) v \(formatter.string(from: Date()))"
        keyTestStatusLabel.textColor = AppTheme.Color.success

        keyTestHintTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resetKeyTestHintIfStale()
            }
        }
    }

    private func resetKeyTestHintIfStale() {
        keyTestStatusLabel.stringValue =
            "Stiskni svou diktovací klávesu (\(HotkeyPreference.current.hintLabel)) — \(AppBrand.displayName) ukáže, jestli ji vidí."
        keyTestStatusLabel.textColor = AppTheme.Color.body
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
            "Povolte tři oprávnění. Bez „Monitorování vstupu“ diktovací klávesa funguje jen s otevřeným oknem \(AppBrand.displayName).",
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

        bundlePathLabel.lineBreakMode = .byTruncatingMiddle

        let microphoneRow = PermissionsPanelBuilder.permissionRow(
            number: "1",
            title: "Mikrofon",
            detail: "Nahrává jen ve chvíli, kdy držíte \(HotkeyPreference.current.hintLabel).",
            badge: microphoneBadge,
            button: microphoneButton
        )

        let accessibilityRow = PermissionsPanelBuilder.permissionRow(
            number: "2",
            title: "Zpřístupnění",
            detail: """
            macOS aplikaci do seznamu nepřidá sama — ani po výzvě. Klepni na tlačítko níže: otevře se Nastavení \
            a ve Finderu uvidíš přesně tuto kopii \(AppBrand.bundleFileName). V Soukromí a zabezpečení → Zpřístupnění klepni na + \
            a vyber tuto aplikaci (nebo ji přetáhni). Starý záznam „\(AppBrand.displayName)“ z jiné složky smaž.
            """,
            badge: accessibilityBadge,
            button: accessibilityButton,
            extraViews: [bundlePathLabel]
        )

        let inputMonitoringRow = PermissionsPanelBuilder.permissionRow(
            number: "3",
            title: "Monitorování vstupu",
            detail: """
            Nutné pro globální diktovací klávesu v Linearu, Cursoru a dalších appkách. Klepni na tlačítko, \
            povol \(AppBrand.displayName) v seznamu Monitorování vstupu (stejná .app jako u Zpřístupnění).
            """,
            badge: inputMonitoringBadge,
            button: inputMonitoringButton
        )

        keyTestStatusLabel.setAccessibilityLabel("Test diktovací klávesy")
        let keyTestCard = AppTheme.card([
            AppTheme.label("Otestuj diktovací klávesu", font: AppTheme.Font.headline, color: AppTheme.Color.title),
            keyTestStatusLabel
        ])

        let helper = AppTheme.label(
            "Pokud klávesa funguje jen s otevřeným \(AppBrand.displayName), chybí Monitorování vstupu. Odeber staré záznamy \(AppBrand.displayName) a přidej /Applications/\(AppBrand.bundleFileName) do obou seznamů.",
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
                inputMonitoringRow,
                keyTestCard,
                footerButtons,
                helper
            ]
        )
        contentStack.setCustomSpacing(AppTheme.Spacing.hero, after: header)
        contentStack.setCustomSpacing(AppTheme.Spacing.intimate, after: footerButtons)
    }

    private func wireActions() {
        microphoneButton.target = self
        microphoneButton.action = #selector(requestMicrophone)
        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibilitySettings)
        inputMonitoringButton.target = self
        inputMonitoringButton.action = #selector(openInputMonitoringSettings)
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
                let granted = PermissionsSnapshotProvider.current.allGranted
                guard granted, self?.hadAllPermissionsWhenOpened == false else { return }
                self?.close()
                self?.onPermissionsGranted?()
            }
        }
    }

    private func refreshPermissionState() {
        let snapshot = PermissionsSnapshotProvider.current
        if snapshot != lastLoggedSnapshot {
            lastLoggedSnapshot = snapshot
            DiagnosticsLogger.log(
                "Permissions refreshed. microphone=\(snapshot.microphone.label), accessibility=\(snapshot.accessibility.label), inputMonitoring=\(snapshot.inputMonitoring.label)"
            )
        }

        microphoneBadge.stringValue = snapshot.microphone.label
        microphoneBadge.textColor = snapshot.microphone.color
        AccessibilitySupport.configure(
            microphoneBadge,
            label: "Mikrofon: \(snapshot.microphone.label)",
            help: snapshot.microphone == .allowed
                ? "Mikrofon je povolený."
                : "Povol mikrofon pro nahrávání při držení diktovací klávesy."
        )
        microphoneButton.isHidden = snapshot.microphone == .allowed

        accessibilityBadge.stringValue = snapshot.accessibility.label
        accessibilityBadge.textColor = snapshot.accessibility.color
        AccessibilitySupport.configure(
            accessibilityBadge,
            label: "Zpřístupnění: \(snapshot.accessibility.label)",
            help: snapshot.accessibility == .allowed
                ? "Zpřístupnění je povolené."
                : "Přidej tuto kopii \(AppBrand.bundleFileName) do Soukromí a zabezpečení → Zpřístupnění."
        )
        accessibilityButton.isHidden = snapshot.accessibility == .allowed

        inputMonitoringBadge.stringValue = snapshot.inputMonitoring.label
        inputMonitoringBadge.textColor = snapshot.inputMonitoring.color
        inputMonitoringButton.isHidden = snapshot.inputMonitoring == .allowed
    }

    @objc private func requestMicrophone() {
        DiagnosticsLogger.log("Microphone permission requested")
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissionState() }
        }
        openMicrophoneSettings()
    }

    @objc private func openInputMonitoringSettings() {
        DiagnosticsLogger.log("Input Monitoring onboarding flow started")
        AppWindowPresenter.activateApp()
        AppWindowPresenter.present(window)
        InputMonitoringSettings.revealRunningAppBundle()
        _ = InputMonitoringSettings.requestAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            InputMonitoringSettings.openPrivacyPane()
            self.refreshPermissionState()
        }
    }

    @objc private func openAccessibilitySettings() {
        DiagnosticsLogger.log("Accessibility onboarding flow started")
        AppWindowPresenter.activateApp()
        AppWindowPresenter.present(window)
        AccessibilitySettings.revealRunningAppBundle()
        _ = AccessibilitySettings.requestTrustPrompt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            AccessibilitySettings.openPrivacyPane()
            self.refreshPermissionState()
        }
    }

    private func requestAccessibilityPromptIfNeeded() {
        guard !didRequestAccessibilityPromptThisSession else { return }
        didRequestAccessibilityPromptThisSession = true
        guard !AccessibilitySettings.isTrusted() else { return }
        _ = AccessibilitySettings.requestTrustPrompt()
    }

    @objc private func checkAgain() {
        DiagnosticsLogger.log("Manual permission recheck requested")
        refreshPermissionState()
        if PermissionsSnapshotProvider.current.allGranted, !hadAllPermissionsWhenOpened {
            close()
            onPermissionsGranted?()
        }
    }

    @objc private func revealCurrentApp() {
        AccessibilitySettings.revealRunningAppBundle()
    }

    private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
