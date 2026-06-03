import Cocoa

/// Nastavení aplikace — hotkey, model, chování (bez oprávnění, bez auto-close).
@MainActor
final class PreferencesWindowController: NSWindowController {
    private let panelBuilder = PreferencesPanelBuilder()
    private var refreshTimer: Timer?
    private let advancedDisclosure = NSButton(title: "Pokročilé", target: nil, action: nil)
    private let advancedPanel = NSView()

    var hotkeyHealthProvider: (() -> HotkeyHealth)? {
        didSet { panelBuilder.hotkeyHealthProvider = hotkeyHealthProvider }
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        AppTheme.configureMainWindow(window, title: "Nastavení")

        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        AppWindowPresenter.activateApp()
        AppWindowPresenter.present(window)
        panelBuilder.refreshMicrophonePicker()
        panelBuilder.refreshHotkeyTapHealthLabel()
        startRefreshTimer()
    }

    override func close() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        super.close()
    }

    private func buildUI() {
        let logo = AppLogoView()
        logo.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 64),
            logo.heightAnchor.constraint(equalToConstant: 64)
        ])

        let title = AppTheme.label("Nastavení", font: AppTheme.Font.title, color: AppTheme.Color.title)

        let headerText = NSStackView(views: [title])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = AppTheme.Spacing.tight

        let header = NSStackView(views: [logo, headerText])
        header.orientation = .horizontal
        header.alignment = .top
        header.spacing = AppTheme.Spacing.stack
        header.translatesAutoresizingMaskIntoConstraints = false
        headerText.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let scrollView = NSScrollView()
        let contentView = NSView()
        window?.contentView = contentView
        AppTheme.pinScrollViewToWindow(scrollView, in: contentView)

        advancedDisclosure.setButtonType(.toggle)
        advancedDisclosure.bezelStyle = .inline
        advancedDisclosure.font = AppTheme.Font.footnote
        advancedDisclosure.state = .off
        advancedDisclosure.target = self
        advancedDisclosure.action = #selector(toggleAdvancedPanel)

        let advancedStack = NSStackView(views: panelBuilder.buildAdvancedCards())
        advancedStack.orientation = .vertical
        advancedStack.alignment = .leading
        advancedStack.spacing = AppTheme.Spacing.stack
        advancedStack.translatesAutoresizingMaskIntoConstraints = false
        advancedPanel.addSubview(advancedStack)
        NSLayoutConstraint.activate([
            advancedStack.leadingAnchor.constraint(equalTo: advancedPanel.leadingAnchor),
            advancedStack.trailingAnchor.constraint(equalTo: advancedPanel.trailingAnchor),
            advancedStack.topAnchor.constraint(equalTo: advancedPanel.topAnchor),
            advancedStack.bottomAnchor.constraint(equalTo: advancedPanel.bottomAnchor)
        ])
        advancedPanel.isHidden = true

        let contentStack = ScrollContentLayout.install(
            in: scrollView,
            arrangedSubviews: [header] + panelBuilder.buildGroupedSections() + [advancedDisclosure, advancedPanel]
        )
        contentStack.setCustomSpacing(AppTheme.Spacing.hero, after: header)
        contentStack.setCustomSpacing(AppTheme.Spacing.tight, after: advancedDisclosure)
    }

    @objc private func toggleAdvancedPanel() {
        advancedPanel.isHidden = advancedDisclosure.state != .on
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.panelBuilder.refreshHotkeyTapHealthLabel()
            }
        }
    }
}
