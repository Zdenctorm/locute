import AppKit

enum RecordingOverlayMode: Equatable {
    case hidden
    case keyHeld
    case recording
    case streamingPreview(confirmed: String, draft: String)
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
    private let previewLabel = NSTextField(labelWithString: "")
    private let dotView = NSView()
    private let statusRow = NSStackView()
    private var pulseTimer: Timer?
    private var currentMode: RecordingOverlayMode = .hidden
    private var lastSyncedState: DictatorState = .idle
    private var hideDelayTimer: Timer?
    private var lastAnnouncedMode: RecordingOverlayMode?

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
        previewLabel.stringValue = ""
        previewLabel.isHidden = true
        panel?.orderOut(nil)
    }

    func updateStreamingPreview(_ preview: StreamingPreview) {
        guard currentMode == .recording || isStreamingPreviewMode(currentMode) else { return }
        currentMode = .streamingPreview(confirmed: preview.confirmedText, draft: preview.draftText)
        ensurePanel()
        apply(currentMode)
        panel?.orderFrontRegardless()
    }

    private func isStreamingPreviewMode(_ mode: RecordingOverlayMode) -> Bool {
        if case .streamingPreview = mode { return true }
        return false
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
            if case .streamingPreview = currentMode {
                break
            } else {
                show(.recording)
            }
        case .transcribing:
            cancelHideDelay()
            show(.transcribing)
        case .injecting:
            cancelHideDelay()
            show(.injecting)
        case .idle:
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
                show(.busy("Počkej — připravuji model"))
            } else {
                hide()
            }
        case .permissionsNeeded:
            cancelHideDelay()
            if rightOptionHeld {
                show(.busy("Nejdřív dokonči nastavení oprávnění"))
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
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 72),
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
        panel.setAccessibilityTitle("Stav diktování")

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
        AccessibilitySupport.configure(dotView, label: "", hidden: true)
        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 10),
            dotView.heightAnchor.constraint(equalToConstant: 10)
        ])

        statusLabel.font = AppTheme.Font.status
        statusLabel.textColor = AppTheme.Color.title
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setAccessibilityElement(false)

        previewLabel.font = AppTheme.Font.footnote
        previewLabel.textColor = AppTheme.Color.body
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.maximumNumberOfLines = 3
        previewLabel.isHidden = true
        previewLabel.setAccessibilityElement(false)

        let textColumn = NSStackView(views: [statusLabel, previewLabel])
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 4

        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 10
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusRow.addArrangedSubview(dotView)
        statusRow.addArrangedSubview(textColumn)
        AccessibilitySupport.configure(
            statusRow,
            label: "Stav diktování",
            help: "Ukazuje, jestli Dictator nahrává, přepisuje nebo vkládá text.",
            role: .group
        )

        let root = NSView()
        root.addSubview(container)
        container.addSubview(statusRow)
        panel.contentView = root

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.topAnchor.constraint(equalTo: root.topAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            statusRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            statusRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            statusRow.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            statusRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        self.panel = panel
        positionPanel()
    }

    private func targetScreen() -> NSScreen? {
        let point = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return screen
        }
        return NSScreen.main
    }

    private func positionPanel() {
        guard let panel, let screen = targetScreen() else { return }
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
            previewLabel.isHidden = true
            dotView.layer?.backgroundColor = AppTheme.Color.recording.cgColor
        case .streamingPreview(let confirmed, let draft):
            statusLabel.stringValue = "Nahrávám — mluv"
            dotView.layer?.backgroundColor = AppTheme.Color.recording.cgColor
            let draftTrimmed = draft.trimmingCharacters(in: .whitespaces)
            let confirmedTrimmed = confirmed.trimmingCharacters(in: .whitespaces)
            if draftTrimmed.isEmpty && confirmedTrimmed.isEmpty {
                previewLabel.isHidden = true
            } else {
                previewLabel.isHidden = false
                if draftTrimmed.isEmpty {
                    previewLabel.stringValue = confirmedTrimmed
                    previewLabel.textColor = AppTheme.Color.title
                } else if confirmedTrimmed.isEmpty {
                    previewLabel.stringValue = draftTrimmed
                    previewLabel.textColor = AppTheme.Color.body.withAlphaComponent(0.75)
                } else {
                    previewLabel.stringValue = "\(confirmedTrimmed) \(draftTrimmed)"
                    previewLabel.textColor = AppTheme.Color.body
                }
            }
        case .transcribing:
            statusLabel.stringValue = "Přepisuji…"
            previewLabel.isHidden = true
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
            statusLabel.stringValue = "Špatná klávesa — drž \(HotkeyPreference.current.hintLabel)"
            dotView.layer?.backgroundColor = AppTheme.Color.warning.cgColor
        case .hidden:
            break
        }

        let label = mode.accessibilityLabel
        if !label.isEmpty {
            statusRow.setAccessibilityLabel(label)
            statusRow.setAccessibilityValue(label)
        }

        if mode.shouldAnnounce, lastAnnouncedMode != mode {
            lastAnnouncedMode = mode
            AccessibilitySupport.announce(label)
        }

        positionPanel()
    }

    private func startPulseIfNeeded(for mode: RecordingOverlayMode) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        guard mode == .keyHeld || mode == .recording || isStreamingPreviewMode(mode) else { return }

        let recording = AppTheme.Color.recording
        var bright = true
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                bright.toggle()
                self?.dotView.layer?.backgroundColor = (
                    bright ? recording : recording.withAlphaComponent(0.35)
                ).cgColor
            }
        }
    }
}
