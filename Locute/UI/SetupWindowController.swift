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
    private var hotkeyObserver: NSObjectProtocol?
    private let bundlePathLabel = AppTheme.label(
        "",
        font: AppTheme.Font.footnote,
        color: AppTheme.Color.body,
        lines: 0
    )
    private let helpDisclosure = NSButton(title: "Potřebuješ pomoc?", target: nil, action: nil)
    private let helpPanel = NSView()
    private let logStatusLabel = AppTheme.label(
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
        "Stiskni diktovací klávesu.",
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
        AppTheme.configureMainWindow(window, title: "Oprávnění")

        super.init(window: window)

        buildUI()
        wireActions()
        refreshHotkeyCopy()
        refreshPermissionState()
        startPolling()
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .locuteHotkeyPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshHotkeyCopy()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        hadAllPermissionsWhenOpened = PermissionsSnapshotProvider.current.allGranted
        AppWindowPresenter.activateApp()
        AppWindowPresenter.present(window)
        bundlePathLabel.stringValue = "Cesta: \(Bundle.main.bundleURL.path)"
        requestAccessibilityPromptIfNeeded()
    }

    override func close() {
        checkTimer?.invalidate()
        checkTimer = nil
        keyTestHintTimer?.invalidate()
        keyTestHintTimer = nil
        if let hotkeyObserver {
            NotificationCenter.default.removeObserver(hotkeyObserver)
        }
        super.close()
    }

    private func refreshHotkeyCopy() {
        resetKeyTestHintIfStale()
    }

    func reportKeyEvent(key: HotkeyKey, isDown: Bool) {
        guard isDown else { return }
        keyTestHintTimer?.invalidate()

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        keyTestStatusLabel.stringValue =
            "Klávesa OK (\(HotkeyPreference.current.hintLabel), \(formatter.string(from: Date())))"
        keyTestStatusLabel.textColor = AppTheme.Color.success

        keyTestHintTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resetKeyTestHintIfStale()
            }
        }
    }

    private func resetKeyTestHintIfStale() {
        keyTestStatusLabel.stringValue = "Stiskni \(HotkeyPreference.current.hintLabel)."
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
            "Dokonči nastavení",
            font: AppTheme.Font.title,
            color: AppTheme.Color.title
        )
        let subtitle = AppTheme.label(
            "Povol tři oprávnění níže.",
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
            detail: "",
            badge: microphoneBadge,
            button: microphoneButton
        )

        let accessibilityRow = PermissionsPanelBuilder.permissionRow(
            number: "2",
            title: "Zpřístupnění",
            detail: "Tlačítko → Nastavení → Zpřístupnění → přidej tuto kopii (+).",
            badge: accessibilityBadge,
            button: accessibilityButton
        )

        let inputMonitoringRow = PermissionsPanelBuilder.permissionRow(
            number: "3",
            title: "Monitorování vstupu",
            detail: "Pro klávesu v jiných appkách.",
            badge: inputMonitoringBadge,
            button: inputMonitoringButton
        )

        keyTestStatusLabel.setAccessibilityLabel("Test diktovací klávesy")
        let keyTestCard = AppTheme.card([
            AppTheme.label("Otestuj klávesu", font: AppTheme.Font.headline, color: AppTheme.Color.title),
            keyTestStatusLabel
        ])

        bundlePathLabel.lineBreakMode = .byTruncatingMiddle
        logStatusLabel.isHidden = true

        helpDisclosure.setButtonType(.toggle)
        helpDisclosure.bezelStyle = .inline
        helpDisclosure.font = AppTheme.Font.footnote
        helpDisclosure.state = .off
        helpDisclosure.target = self
        helpDisclosure.action = #selector(toggleHelpPanel)

        let helpHint = AppTheme.label(
            "Klávesa nefunguje globálně? Zkontroluj Monitorování vstupu a Zpřístupnění.",
            font: AppTheme.Font.footnote,
            color: AppTheme.Color.body,
            lines: 0
        )

        let helpButtons = NSStackView(views: [revealAppButton, copyLogButton])
        helpButtons.orientation = .horizontal
        helpButtons.alignment = .centerY
        helpButtons.spacing = AppTheme.Spacing.row

        let helpStack = NSStackView(views: [helpHint, bundlePathLabel, helpButtons, logStatusLabel])
        helpStack.orientation = .vertical
        helpStack.alignment = .leading
        helpStack.spacing = AppTheme.Spacing.tight
        helpPanel.addSubview(helpStack)
        helpStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            helpStack.leadingAnchor.constraint(equalTo: helpPanel.leadingAnchor),
            helpStack.trailingAnchor.constraint(equalTo: helpPanel.trailingAnchor),
            helpStack.topAnchor.constraint(equalTo: helpPanel.topAnchor),
            helpStack.bottomAnchor.constraint(equalTo: helpPanel.bottomAnchor)
        ])
        helpPanel.isHidden = true

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footerButtons = NSStackView(views: [checkAgainButton, footerSpacer])
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
                helpDisclosure,
                helpPanel
            ]
        )
        contentStack.setCustomSpacing(AppTheme.Spacing.hero, after: header)
        contentStack.setCustomSpacing(AppTheme.Spacing.intimate, after: footerButtons)
        contentStack.setCustomSpacing(AppTheme.Spacing.tight, after: helpDisclosure)
    }

    @objc private func toggleHelpPanel() {
        helpPanel.isHidden = helpDisclosure.state != .on
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
        logStatusLabel.isHidden = false
        logStatusLabel.stringValue = "Log ve schránce."
        logStatusLabel.textColor = AppTheme.Color.success
        if helpDisclosure.state == .off {
            helpDisclosure.state = .on
            helpPanel.isHidden = false
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
            help: snapshot.microphone == .allowed ? "Mikrofon je povolený." : "Povol mikrofon."
        )
        microphoneButton.isHidden = snapshot.microphone == .allowed

        accessibilityBadge.stringValue = snapshot.accessibility.label
        accessibilityBadge.textColor = snapshot.accessibility.color
        AccessibilitySupport.configure(
            accessibilityBadge,
            label: "Zpřístupnění: \(snapshot.accessibility.label)",
            help: snapshot.accessibility == .allowed ? "Zpřístupnění je povolené." : "Přidej tuto kopii do Zpřístupnění."
        )
        accessibilityButton.isHidden = snapshot.accessibility == .allowed

        inputMonitoringBadge.stringValue = snapshot.inputMonitoring.label
        inputMonitoringBadge.textColor = snapshot.inputMonitoring.color
        AccessibilitySupport.configure(
            inputMonitoringBadge,
            label: "Monitorování vstupu: \(snapshot.inputMonitoring.label)",
            help: snapshot.inputMonitoring == .allowed
                ? "Globální klávesa funguje."
                : "Povol Monitorování vstupu."
        )
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
