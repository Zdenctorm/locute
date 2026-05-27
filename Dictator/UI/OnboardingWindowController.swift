import AVFoundation
import Cocoa

@MainActor
final class OnboardingWindowController: NSWindowController {
    var onFinished: (() -> Void)?
    var onPermissionsChanged: (() -> Void)?
    var onRequestContinueStartup: (() -> Void)?

    private static let stepCount = 6
    private var currentStep = 0
    private var keyDetected = false
    private var downloadReady = false
    private var permissionTimer: Timer?
    private var keyTestHintTimer: Timer?
    private var didRequestAccessibilityPrompt = false

    private let stepTitleLabel = AppTheme.label("", font: AppTheme.Font.title, color: AppTheme.Color.title)
    private let stepBodyLabel = AppTheme.label("", font: AppTheme.Font.body, color: AppTheme.Color.body, lines: 0)
    private let stepCardContainer = NSStackView()
    private let backButton = AppTheme.secondaryButton("Zpět", target: nil, action: nil)
    private let nextButton = AppTheme.primaryButton("Pokračovat", target: nil, action: nil)
    private let finishButton = AppTheme.primaryButton("Dokončit", target: nil, action: nil)

    private let microphoneBadge = AppTheme.badge("Chybí", color: AppTheme.Color.warning)
    private let accessibilityBadge = AppTheme.badge("Chybí", color: AppTheme.Color.warning)
    private let microphoneButton = AppTheme.secondaryButton("Povolit mikrofon", target: nil, action: nil)
    private let accessibilityButton = AppTheme.secondaryButton("Přidat do Zpřístupnění…", target: nil, action: nil)
    private let bundlePathLabel = AppTheme.label("", font: AppTheme.Font.footnote, color: AppTheme.Color.body, lines: 0)

    private let keyTestStatusLabel = AppTheme.label("Stiskni Option (⌥) — Dictator ukáže, jestli klávesu vidí.", font: AppTheme.Font.body, color: AppTheme.Color.body, lines: 0)

    private let downloadTitleLabel = AppTheme.label("Připravuji model…", font: AppTheme.Font.headline, color: AppTheme.Color.title)
    private let downloadProgressIndicator = NSProgressIndicator()
    private let downloadDetailLabel = AppTheme.label("", font: AppTheme.Font.body, color: AppTheme.Color.body, lines: 0)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        AppTheme.configureMainWindow(window, title: "Průvodce nastavením")
        super.init(window: window)
        buildUI()
        wireActions()
        showStep(0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        AppWindowPresenter.activateApp()
        AppWindowPresenter.present(window)
        bundlePathLabel.stringValue = "Aktuální kopie: \(Bundle.main.bundleURL.path)"
        refreshPermissions()
        if !didRequestAccessibilityPrompt {
            didRequestAccessibilityPrompt = true
            if !AccessibilitySettings.isTrusted() { _ = AccessibilitySettings.requestTrustPrompt() }
        }
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    override func close() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        keyTestHintTimer?.invalidate()
        keyTestHintTimer = nil
        super.close()
    }

    func refreshPermissions() {
        let s = PermissionsWindowController.currentSnapshot
        for (badge, state, button) in [
            (microphoneBadge, s.microphone, microphoneButton),
            (accessibilityBadge, s.accessibility, accessibilityButton)
        ] {
            badge.stringValue = state.label
            badge.textColor = state.color
            button.isHidden = state == .allowed
        }
        if s.allGranted { onPermissionsChanged?() }
        updateNavigation()
    }

    func reportKeyEvent(key: HotkeyKey, isDown: Bool) {
        guard isDown else { return }
        keyTestHintTimer?.invalidate()
        switch key {
        case .option, .leftOption:
            keyDetected = true
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            keyTestStatusLabel.stringValue = "Option zachycena v \(formatter.string(from: Date()))"
            keyTestStatusLabel.textColor = AppTheme.Color.success
            updateNavigation()
        }
        keyTestHintTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resetKeyTestHintIfStale() }
        }
    }

    func updateDownloadProgress(fraction: Double, detail: String) {
        downloadProgressIndicator.isIndeterminate = fraction <= 0
        if fraction > 0 {
            downloadProgressIndicator.isIndeterminate = false
            downloadProgressIndicator.doubleValue = min(max(fraction, 0), 1)
        }
        downloadDetailLabel.stringValue = detail
        downloadTitleLabel.stringValue = fraction >= 1
            ? "Model je připravený"
            : "Stahuji Whisper (\(TranscriptionModelPreference.current.label))"
        downloadReady = fraction >= 1
        updateNavigation()
    }

    private func buildUI() {
        let logo = AppLogoView()
        logo.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 64),
            logo.heightAnchor.constraint(equalToConstant: 64)
        ])

        stepCardContainer.orientation = .vertical
        stepCardContainer.alignment = .leading
        stepCardContainer.spacing = AppTheme.Spacing.row

        downloadProgressIndicator.minValue = 0
        downloadProgressIndicator.maxValue = 1
        downloadProgressIndicator.isIndeterminate = true
        downloadProgressIndicator.style = .bar
        downloadProgressIndicator.controlSize = .regular

        bundlePathLabel.lineBreakMode = .byTruncatingMiddle
        finishButton.isHidden = true

        let header = NSStackView(views: [logo, stepTitleLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = AppTheme.Spacing.stack

        let nav = NSStackView(views: [backButton, nextButton, finishButton])
        nav.orientation = .horizontal
        nav.alignment = .centerY
        nav.spacing = AppTheme.Spacing.row

        let root = NSStackView(views: [header, stepBodyLabel, stepCardContainer, nav])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = AppTheme.Spacing.stack
        root.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        window?.contentView = contentView
        contentView.addSubview(root)
        let pad = AppTheme.Spacing.windowPadding
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: pad),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -pad),
            stepTitleLabel.widthAnchor.constraint(equalTo: root.widthAnchor),
            stepBodyLabel.widthAnchor.constraint(equalTo: root.widthAnchor),
            stepCardContainer.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }

    private func wireActions() {
        backButton.target = self
        backButton.action = #selector(goBack)
        nextButton.target = self
        nextButton.action = #selector(goNext)
        finishButton.target = self
        finishButton.action = #selector(finish)
        microphoneButton.target = self
        microphoneButton.action = #selector(requestMicrophone)
        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibilitySettings)
    }

    private func showStep(_ step: Int) {
        currentStep = step
        stepCardContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }

        switch step {
        case 0:
            stepTitleLabel.stringValue = "Vítejte v Dictatoru"
            stepBodyLabel.stringValue =
                "Soukromé offline diktování v češtině. Podrž Option (⌥), mluv a pusť — text se vloží tam, kde máš kurzor."
            stepCardContainer.addArrangedSubview(AppTheme.card([
                AppTheme.label("Jak to funguje", font: AppTheme.Font.headline, color: AppTheme.Color.title),
                AppTheme.label(
                    "Žádná data neopouštějí Mac. Výchozí turbo model má ~630 MB (ne 3 GB) — stáhne se jednou při prvním spuštění.",
                    font: AppTheme.Font.body,
                    color: AppTheme.Color.body,
                    lines: 0
                )
            ]))
        case 1:
            stepTitleLabel.stringValue = "Oprávnění"
            stepBodyLabel.stringValue = "Dictator potřebuje mikrofon a Zpřístupnění — obojí zůstává jen na tvém Macu."
            stepCardContainer.addArrangedSubview(permissionsCard())
            refreshPermissions()
        case 2:
            stepTitleLabel.stringValue = "Test klávesy"
            stepBodyLabel.stringValue = "Ověříme, že Dictator vidí tvou diktovací klávesu."
            stepCardContainer.addArrangedSubview(AppTheme.card([
                AppTheme.label("Stiskni Option (⌥)", font: AppTheme.Font.headline, color: AppTheme.Color.title),
                keyTestStatusLabel
            ]))
        case 3:
            stepTitleLabel.stringValue = "Stažení modelu"
            stepBodyLabel.stringValue = "První spuštění stahuje lokální Whisper model. Nezavírej aplikaci."
            stepCardContainer.addArrangedSubview(AppTheme.card([
                downloadTitleLabel, downloadProgressIndicator, downloadDetailLabel
            ]))
            if !downloadReady {
                downloadDetailLabel.stringValue = "Čekám na start stahování…"
                onRequestContinueStartup?()
            }
        case 4:
            stepTitleLabel.stringValue = "Gatekeeper"
            stepBodyLabel.stringValue = "Dictator zatím nemá Apple notarizaci — macOS může varovat při prvním otevření."
            stepCardContainer.addArrangedSubview(AppTheme.card([
                AppTheme.label("Jak spustit nepodepsanou appku", font: AppTheme.Font.headline, color: AppTheme.Color.title),
                AppTheme.label(
                    "Klikni pravým tlačítkem na Dictator.app → Otevřít → potvrď Otevřít. Příště stačí dvojklik.",
                    font: AppTheme.Font.body,
                    color: AppTheme.Color.body,
                    lines: 0
                )
            ]))
        default:
            stepTitleLabel.stringValue = "Hotovo"
            stepBodyLabel.stringValue = "Dictator běží v menu baru. Můžeš začít diktovat."
            stepCardContainer.addArrangedSubview(AppTheme.card([
                AppTheme.label(
                    "Podrž \(HotkeyPreference.current.hintLabel) a mluv",
                    font: AppTheme.Font.headline,
                    color: AppTheme.Color.title
                ),
                AppTheme.label(
                    "Okno můžeš skrýt — Dictator zůstane v horní liště.",
                    font: AppTheme.Font.body,
                    color: AppTheme.Color.body,
                    lines: 0
                )
            ]))
        }
        updateNavigation()
    }

    private func permissionsCard() -> NSView {
        func row(_ title: String, _ detail: String, _ badge: NSTextField, _ button: NSButton, _ extra: [NSView] = []) -> NSView {
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let titleRow = NSStackView(views: [
                AppTheme.label(title, font: AppTheme.Font.headline, color: AppTheme.Color.title),
                spacer, badge
            ])
            titleRow.orientation = .horizontal
            titleRow.alignment = .firstBaseline
            var items: [NSView] = [titleRow, AppTheme.label(detail, font: AppTheme.Font.body, color: AppTheme.Color.body, lines: 0)]
            items.append(contentsOf: extra)
            items.append(button)
            let stack = NSStackView(views: items)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = AppTheme.Spacing.tight
            return stack
        }
        let stack = NSStackView(views: [
            row("Mikrofon", "Nahrává jen při držení Option.", microphoneBadge, microphoneButton),
            row("Zpřístupnění", "V Nastavení → Soukromí → Zpřístupnění přidej tuto kopii Dictator.app.", accessibilityBadge, accessibilityButton, [bundlePathLabel])
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = AppTheme.Spacing.section
        return AppTheme.card([stack])
    }

    private func updateNavigation() {
        backButton.isHidden = currentStep == 0
        let isLast = currentStep == Self.stepCount - 1
        nextButton.isHidden = isLast
        finishButton.isHidden = !isLast
        nextButton.isEnabled = canAdvance(from: currentStep)
    }

    private func canAdvance(from step: Int) -> Bool {
        switch step {
        case 1: return PermissionsWindowController.currentSnapshot.allGranted
        case 2: return keyDetected
        case 3: return downloadReady
        default: return true
        }
    }

    @objc private func goBack() {
        guard currentStep > 0 else { return }
        showStep(currentStep - 1)
    }

    @objc private func goNext() {
        guard canAdvance(from: currentStep), currentStep < Self.stepCount - 1 else { return }
        showStep(currentStep + 1)
    }

    @objc private func finish() {
        OnboardingPreference.markOnboardingComplete()
        close()
        onFinished?()
    }

    @objc private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openAccessibilitySettings() {
        AppWindowPresenter.activateApp()
        AppWindowPresenter.present(window)
        AccessibilitySettings.revealRunningAppBundle()
        _ = AccessibilitySettings.requestTrustPrompt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            AccessibilitySettings.openPrivacyPane()
            self?.refreshPermissions()
        }
    }

    private func resetKeyTestHintIfStale() {
        guard !keyDetected else { return }
        keyTestStatusLabel.stringValue = "Stiskni Option (⌥) — Dictator ukáže, jestli klávesu vidí."
        keyTestStatusLabel.textColor = AppTheme.Color.body
    }
}
