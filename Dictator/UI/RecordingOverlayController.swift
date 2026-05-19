import AppKit

enum RecordingOverlayMode: Equatable {
    case hidden
    case keyHeld
    case recording
    case transcribing
    case injecting
    case injectionSuccess
    case busy(String)
    case wrongKey
}

@MainActor
final class RecordingOverlayController {
    private var panel: NSPanel?
    private let statusLabel = NSTextField(labelWithString: "")
    private let dotView = NSView()
    private var pulseTimer: Timer?
    private var currentMode: RecordingOverlayMode = .hidden
    private var lastSyncedState: DictatorState = .idle
    private var hideDelayTimer: Timer?

    func show(_ mode: RecordingOverlayMode) {
        guard mode != .hidden else {
            hide()
            return
        }
        currentMode = mode
        ensurePanel()
        apply(mode)
        panel?.orderFrontRegardless()
        startPulseIfNeeded(for: mode)
    }

    func hide() {
        currentMode = .hidden
        pulseTimer?.invalidate()
        pulseTimer = nil
        panel?.orderOut(nil)
    }

    func sync(appState: DictatorState, rightOptionHeld: Bool) {
        let previous = lastSyncedState
        lastSyncedState = appState

        if rightOptionHeld, appState == .idle {
            cancelHideDelay()
            show(.keyHeld)
            return
        }

        switch appState {
        case .recording:
            cancelHideDelay()
            show(.recording)
        case .transcribing:
            cancelHideDelay()
            show(.transcribing)
        case .injecting:
            cancelHideDelay()
            show(.injecting)
        case .idle:
            // Just finished injecting? Linger briefly on success before hiding.
            if previous == .injecting, !rightOptionHeld {
                show(.injectionSuccess)
                scheduleHide(after: 0.7)
            } else if rightOptionHeld {
                cancelHideDelay()
                show(.keyHeld)
            } else {
                cancelHideDelay()
                hide()
            }
        case .error:
            cancelHideDelay()
            if rightOptionHeld {
                show(.keyHeld)
            } else {
                hide()
            }
        case .modelDownloading, .modelLoading, .launching:
            cancelHideDelay()
            if rightOptionHeld {
                show(.busy("Počkejte — připravuji model"))
            } else {
                hide()
            }
        case .permissionsNeeded:
            cancelHideDelay()
            if rightOptionHeld {
                show(.busy("Nejdřív dokončete nastavení oprávnění"))
            } else {
                hide()
            }
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideDelayTimer?.invalidate()
        hideDelayTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func cancelHideDelay() {
        hideDelayTimer?.invalidate()
        hideDelayTimer = nil
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false

        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 5
        dotView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 10),
            dotView.heightAnchor.constraint(equalToConstant: 10)
        ])

        statusLabel.font = AppTheme.Font.status
        statusLabel.textColor = AppTheme.Color.title
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 2

        let row = NSStackView(views: [dotView, statusLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(container)
        container.addSubview(row)
        panel.contentView = root

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.topAnchor.constraint(equalTo: root.topAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        self.panel = panel
        positionPanel()
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = panel.frame
        let x = screen.frame.midX - frame.width / 2
        let y = screen.visibleFrame.maxY - frame.height - 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func apply(_ mode: RecordingOverlayMode) {
        switch mode {
        case .keyHeld:
            statusLabel.stringValue = "Držíš \(HotkeyPreference.current.hintLabel)"
            dotView.layer?.backgroundColor = AppTheme.Color.recording.cgColor
        case .recording:
            statusLabel.stringValue = "Nahrávám — mluv"
            dotView.layer?.backgroundColor = AppTheme.Color.recording.cgColor
        case .transcribing:
            statusLabel.stringValue = "Přepisuji…"
            dotView.layer?.backgroundColor = AppTheme.Color.accent.cgColor
        case .injecting:
            statusLabel.stringValue = "Vkládám text…"
            dotView.layer?.backgroundColor = AppTheme.Color.accent.cgColor
        case .injectionSuccess:
            statusLabel.stringValue = "Vloženo"
            dotView.layer?.backgroundColor = AppTheme.Color.success.cgColor
        case .busy(let message):
            statusLabel.stringValue = message
            dotView.layer?.backgroundColor = AppTheme.Color.warning.cgColor
        case .wrongKey:
            statusLabel.stringValue = "To je levý Option — drž pravý"
            dotView.layer?.backgroundColor = AppTheme.Color.warning.cgColor
        case .hidden:
            break
        }
        positionPanel()
    }

    private func startPulseIfNeeded(for mode: RecordingOverlayMode) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        guard mode == .keyHeld || mode == .recording else { return }

        var bright = true
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                bright.toggle()
                self?.dotView.layer?.backgroundColor = (bright ? NSColor.systemRed : NSColor.systemRed.withAlphaComponent(0.35)).cgColor
            }
        }
    }
}
