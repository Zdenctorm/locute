import AppKit

enum RecordingOverlayMode: Equatable {
    case hidden
    case keyHeld
    case recording
    case streamingPreview(confirmed: String, draft: String)
    case transcribing
    case injecting
    case injectionSuccess
    case injectionFailed(String)
    case busy(String)
    case wrongKey
}

/// Kompaktní recording pill (Whispur vzor) — ne banner. Tečka + waveform + krátký stav + Esc.
@MainActor
final class RecordingOverlayController {
    private static let pillWidth: CGFloat = 300
    private static let pillHeight: CGFloat = 44

    private var panel: NSPanel?
    private let statusLabel = NSTextField(labelWithString: "")
    private let escHintLabel = NSTextField(labelWithString: "Esc")
    private let dotView = NSView()
    private let pillRow = NSStackView()
    private let levelMeterView = AudioLevelMeterView()
    private var pulseTimer: Timer?
    private var currentMode: RecordingOverlayMode = .hidden
    private var lastSyncedState: LocuteState = .idle
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
        levelMeterView.setLevel(0)
        panel?.orderOut(nil)
    }

    func showTransientFeedback(_ message: String, duration: TimeInterval = 4.5) {
        cancelHideDelay()
        show(.busy(message))
        scheduleHide(after: duration)
    }

    func updateStreamingPreview(_ preview: StreamingPreview) {
        guard currentMode == .recording || isStreamingPreviewMode(currentMode) else { return }
        currentMode = .streamingPreview(confirmed: preview.confirmedText, draft: preview.draftText)
        ensurePanel()
        apply(currentMode)
        panel?.orderFrontRegardless()
    }

    func updateAudioLevel(_ normalized: Float) {
        guard modeShowsMeter(currentMode) else { return }
        levelMeterView.setLevel(normalized)
    }

    private func isStreamingPreviewMode(_ mode: RecordingOverlayMode) -> Bool {
        if case .streamingPreview = mode { return true }
        return false
    }

    func sync(appState: LocuteState, rightOptionHeld: Bool) {
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
                switch currentMode {
                case .injectionSuccess:
                    scheduleAutoHide(after: 0.7)
                case .injectionFailed:
                    break
                default:
                    hide()
                }
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
                show(.busy("Počkej — model"))
            } else {
                hide()
            }
        case .permissionsNeeded:
            cancelHideDelay()
            if rightOptionHeld {
                show(.busy("Dokonči nastavení"))
            } else {
                hide()
            }
        }
    }

    func scheduleAutoHide(after delay: TimeInterval) {
        scheduleHide(after: delay)
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
            contentRect: NSRect(x: 0, y: 0, width: Self.pillWidth, height: Self.pillHeight),
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
        container.layer?.cornerRadius = Self.pillHeight / 2
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

        statusLabel.font = AppTheme.Font.footnote
        statusLabel.textColor = AppTheme.Color.title
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setAccessibilityElement(false)

        escHintLabel.font = AppTheme.Font.footnote
        escHintLabel.textColor = AppTheme.Color.body.withAlphaComponent(0.85)
        escHintLabel.setContentHuggingPriority(.required, for: .horizontal)
        escHintLabel.setAccessibilityLabel("Stiskni Esc pro zrušení nahrávání")
        escHintLabel.setAccessibilityElement(false)

        levelMeterView.translatesAutoresizingMaskIntoConstraints = false
        levelMeterView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        pillRow.orientation = .horizontal
        pillRow.alignment = .centerY
        pillRow.spacing = 10
        pillRow.translatesAutoresizingMaskIntoConstraints = false
        pillRow.addArrangedSubview(dotView)
        pillRow.addArrangedSubview(levelMeterView)
        pillRow.addArrangedSubview(statusLabel)
        pillRow.addArrangedSubview(escHintLabel)
        AccessibilitySupport.configure(
            pillRow,
            label: "Stav diktování",
            help: "Kompaktní indikátor nahrávání. Esc zruší.",
            role: .group
        )

        let root = NSView()
        root.addSubview(container)
        container.addSubview(pillRow)
        panel.contentView = root

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.topAnchor.constraint(equalTo: root.topAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            pillRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            pillRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            pillRow.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            pillRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),

            levelMeterView.widthAnchor.constraint(greaterThanOrEqualToConstant: 88)
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
        let x = screen.frame.midX - Self.pillWidth / 2
        let y = screen.visibleFrame.maxY - Self.pillHeight - 10
        panel.setFrame(
            NSRect(x: x, y: y, width: Self.pillWidth, height: Self.pillHeight),
            display: false
        )
    }

    private func apply(_ mode: RecordingOverlayMode) {
        let showsMeter = modeShowsMeter(mode)
        levelMeterView.isHidden = !showsMeter
        escHintLabel.isHidden = !showsRecordingUI(mode)

        switch mode {
        case .keyHeld:
            statusLabel.stringValue = "Drž a mluv"
            dotView.layer?.backgroundColor = AppTheme.Color.recording.cgColor
        case .recording:
            statusLabel.stringValue = "Pusť → přepis"
            dotView.layer?.backgroundColor = AppTheme.Color.recording.cgColor
        case .streamingPreview(let confirmed, let draft):
            dotView.layer?.backgroundColor = AppTheme.Color.recording.cgColor
            let text = Self.compactPreview(confirmed: confirmed, draft: draft)
            statusLabel.stringValue = text.isEmpty ? "Pusť → přepis" : text
        case .transcribing:
            statusLabel.stringValue = "Přepisuji…"
            dotView.layer?.backgroundColor = AppTheme.Color.accent.cgColor
        case .injecting:
            statusLabel.stringValue = "Vkládám…"
            dotView.layer?.backgroundColor = AppTheme.Color.accent.cgColor
        case .injectionSuccess:
            statusLabel.stringValue = "Vloženo"
            dotView.layer?.backgroundColor = AppTheme.Color.success.cgColor
        case .injectionFailed:
            statusLabel.stringValue = "Nepodařilo se vložit"
            dotView.layer?.backgroundColor = AppTheme.resolved(AppTheme.Color.danger, for: dotView).cgColor
        case .busy(let message):
            statusLabel.stringValue = Self.truncate(message, max: 36)
            dotView.layer?.backgroundColor = AppTheme.Color.warning.cgColor
        case .wrongKey:
            statusLabel.stringValue = "Drž \(HotkeyPreference.current.hintLabel)"
            dotView.layer?.backgroundColor = AppTheme.Color.warning.cgColor
        case .hidden:
            break
        }

        let label = mode.accessibilityLabel
        if !label.isEmpty {
            pillRow.setAccessibilityLabel(label)
            pillRow.setAccessibilityValue(label)
        }

        if mode.shouldAnnounce, lastAnnouncedMode != mode {
            lastAnnouncedMode = mode
            AccessibilitySupport.announce(label)
        }

        positionPanel()
    }

    private func modeShowsMeter(_ mode: RecordingOverlayMode) -> Bool {
        switch mode {
        case .recording, .streamingPreview, .keyHeld:
            return true
        default:
            return false
        }
    }

    private func showsRecordingUI(_ mode: RecordingOverlayMode) -> Bool {
        switch mode {
        case .recording, .streamingPreview, .keyHeld:
            return true
        default:
            return false
        }
    }

    private static func compactPreview(confirmed: String, draft: String) -> String {
        let draftTrimmed = draft.trimmingCharacters(in: .whitespaces)
        let confirmedTrimmed = confirmed.trimmingCharacters(in: .whitespaces)
        let combined: String
        if draftTrimmed.isEmpty { combined = confirmedTrimmed }
        else if confirmedTrimmed.isEmpty { combined = draftTrimmed }
        else { combined = "\(confirmedTrimmed) \(draftTrimmed)" }
        return truncate(combined, max: 42)
    }

    private static func truncate(_ text: String, max: Int) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard collapsed.count > max else { return collapsed }
        return String(collapsed.prefix(max)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func startPulseIfNeeded(for mode: RecordingOverlayMode) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        guard mode == .keyHeld || mode == .recording || isStreamingPreviewMode(mode) else { return }

        if AccessibilitySupport.shouldReduceMotion {
            dotView.layer?.backgroundColor = AppTheme.Color.recording.cgColor
            return
        }

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
