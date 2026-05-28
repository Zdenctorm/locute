import ApplicationServices
import Cocoa
import CoreGraphics

enum TextInjectResult: Sendable {
    case success(method: String)
    case failed(reason: String)

    var succeeded: Bool {
        if case .success = self { return true }
        return false
    }
}

// MARK: - TextInjector

enum TextInjector {
    /// Injects text into `targetApp` (the app that was frontmost when the user released Option).
    /// Native apps → Accessibility API. Electron/browser apps → clipboard + simulated Cmd+V.
    static func inject(text: String, into targetApp: NSRunningApplication?) async -> TextInjectResult {
        DiagnosticsLogger.log("Paste: start (chars=\(text.count))")

        let bundleID = targetApp?.bundleIdentifier
        let appName = targetApp?.localizedName ?? "?"
        let prefersCommandV = CommandVPastePreferringBundles.prefersCommandV(bundleID: bundleID)
        let skipLeadingSpace = prefersCommandV && isTerminalLike(bundleID: bundleID)

        let spacingContext = await MainActor.run { readInsertionSpacingContext() }
        let replacingSelection = !(spacingContext?.selectedText?.isEmpty ?? true)
        let prefix = InsertionSpacing.leadingPrefix(
            for: text,
            context: spacingContext,
            replacingSelection: replacingSelection,
            skipForTerminalPaste: skipLeadingSpace
        )
        let payload = prefix + text

        let steps = PasteInsertionStep.ordered(prefersCommandVFirst: prefersCommandV)
        DiagnosticsLogger.log(
            "Paste: target app=\(appName) bundle=\(bundleID ?? "?") prefersCommandV=\(prefersCommandV) steps=\(steps.map(\.rawValue).joined(separator: "→")) leadingPrefixLen=\(prefix.count)"
        )

        for step in steps {
            switch step {
            case .accessibility:
                await activateTargetAppIfNeeded(targetApp)
                let ok = await MainActor.run {
                    injectViaAccessibility(text: payload, spacingContext: spacingContext)
                }
                if ok {
                    DiagnosticsLogger.log("Paste: done via AX")
                    return .success(method: "AX")
                }
                DiagnosticsLogger.log("Paste: AX path did not apply; trying next step")
            case .commandV:
                await activateTargetAppIfNeeded(targetApp)
                let result = await injectViaClipboard(text: payload)
                if result.succeeded {
                    return result
                }
                if case .failed(let reason) = result {
                    DiagnosticsLogger.log("Paste: Cmd+V path failed (\(reason)); trying next step")
                }
            }
        }

        return .failed(reason: "Nepodařilo se vložit text do aktivní aplikace")
    }

    private static func activateTargetAppIfNeeded(_ targetApp: NSRunningApplication?) async {
        guard let targetApp else { return }
        await MainActor.run { _ = targetApp.activate(options: .activateIgnoringOtherApps) }
        try? await Task.sleep(for: .milliseconds(150))
    }

    // MARK: - Clipboard + Cmd+V

    @MainActor
    private static func injectViaClipboard(text: String) async -> TextInjectResult {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let maxChangeCount = snapshot.maxChangeCountAfterOurWrites

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            DiagnosticsLogger.log("Paste: clipboard write failed")
            return .failed(reason: "Nepodařilo se zapsat text do schránky")
        }

        guard simulateCmdV() else {
            snapshot.restore(to: pasteboard, maxChangeCount: maxChangeCount)
            DiagnosticsLogger.log("Paste: Cmd+V event creation failed")
            return .failed(reason: "Nepodařilo se simulovat Cmd+V")
        }

        DiagnosticsLogger.log("Paste: done via Cmd+V")
        try? await Task.sleep(for: .milliseconds(400))
        snapshot.restore(to: pasteboard, maxChangeCount: maxChangeCount)
        return .success(method: "Cmd+V")
    }

    @MainActor
    private static func simulateCmdV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        return true
    }

    // MARK: - Accessibility (native AppKit apps)

    @MainActor
    private static func injectViaAccessibility(
        text: String,
        spacingContext: InsertionSpacing.Context?
    ) -> Bool {
        guard AXIsProcessTrusted() else {
            DiagnosticsLogger.log("Paste: AX not trusted")
            return false
        }

        let system = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            DiagnosticsLogger.log("Paste: AX no focused element")
            return false
        }
        let element = unsafeBitCast(ref, to: AXUIElement.self)

        if let selected = spacingContext?.selectedText, !selected.isEmpty {
            if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
                return true
            }
        }

        if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            return true
        }

        var currentRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentRef)
        let current = (currentRef as? String) ?? ""
        let separator: String
        if text.hasPrefix(" ") {
            separator = ""
        } else {
            separator = current.isEmpty || current.hasSuffix(" ") || current.hasSuffix("\n") ? "" : " "
        }
        return AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            (current + separator + text) as CFTypeRef
        ) == .success
    }

    @MainActor
    private static func readInsertionSpacingContext() -> InsertionSpacing.Context? {
        guard AXIsProcessTrusted() else { return nil }

        let system = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = unsafeBitCast(ref, to: AXUIElement.self)

        var selectedRef: CFTypeRef?
        let selectedText = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        ) == .success ? (selectedRef as? String) : nil

        var valueRef: CFTypeRef?
        let fullValue = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        ) == .success ? (valueRef as? String) : nil

        var rangeRef: CFTypeRef?
        var selectedRange: NSRange?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success,
           let rangeRef,
           CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            let axValue = rangeRef as! AXValue
            if AXValueGetType(axValue) == .cfRange {
                var cfRange = CFRange()
                if AXValueGetValue(axValue, .cfRange, &cfRange) {
                    selectedRange = NSRange(location: cfRange.location, length: cfRange.length)
                }
            }
        }

        if selectedText == nil, fullValue == nil, selectedRange == nil {
            return nil
        }

        return InsertionSpacing.Context(
            selectedText: selectedText,
            fullValue: fullValue,
            selectedRange: selectedRange
        )
    }

    private static func isTerminalLike(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        if CommandVPastePreferringBundles.prefersCommandV(bundleID: bundleID) {
            let lower = bundleID.lowercased()
            return lower.contains("terminal") || lower.contains("iterm") || lower.contains("wezterm")
                || lower.contains("warp") || lower.contains("kitty") || lower.contains("alacritty")
        }
        return false
    }
}
