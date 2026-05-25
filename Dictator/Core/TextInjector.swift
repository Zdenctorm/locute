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

// MARK: - ClipboardSnapshot

/// Captures and restores the full NSPasteboard state across all types and items.
/// Used to preserve the user's clipboard contents around Cmd+V paste injection.
private struct ClipboardSnapshot {
    private struct Entry {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    private let items: [[Entry]]

    static func capture() -> ClipboardSnapshot {
        var result: [[Entry]] = []
        for pbItem in NSPasteboard.general.pasteboardItems ?? [] {
            let entries = pbItem.types.compactMap { type -> Entry? in
                guard let data = pbItem.data(forType: type) else { return nil }
                return Entry(type: type, data: data)
            }
            if !entries.isEmpty { result.append(entries) }
        }
        return ClipboardSnapshot(items: result)
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let pbItems = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for entry in entries { item.setData(entry.data, forType: entry.type) }
            return item
        }
        pasteboard.writeObjects(pbItems)
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

        DiagnosticsLogger.log("Paste: target app=\(appName) bundle=\(bundleID ?? "?") prefersCommandV=\(prefersCommandV)")

        // For native apps try AX first — doesn't touch the clipboard
        if !prefersCommandV {
            let ok = await MainActor.run { injectViaAccessibility(text: text) }
            if ok {
                DiagnosticsLogger.log("Paste: done via AX")
                return .success(method: "AX")
            }
            DiagnosticsLogger.log("Paste: AX failed, trying clipboard")
        }

        // Re-activate the target app before paste — focus may have drifted during transcription
        if let targetApp {
            await MainActor.run { _ = targetApp.activate(options: .activateIgnoringOtherApps) }
            try? await Task.sleep(for: .milliseconds(150))
        }

        return await injectViaClipboard(text: text)
    }

    // MARK: - Clipboard + Cmd+V

    @MainActor
    private static func injectViaClipboard(text: String) async -> TextInjectResult {
        let snapshot = ClipboardSnapshot.capture()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            DiagnosticsLogger.log("Paste: clipboard write failed")
            return .failed(reason: "Nepodařilo se zapsat text do schránky")
        }

        guard simulateCmdV() else {
            snapshot.restore()
            DiagnosticsLogger.log("Paste: Cmd+V event creation failed")
            return .failed(reason: "Nepodařilo se simulovat Cmd+V")
        }

        DiagnosticsLogger.log("Paste: done via Cmd+V")
        // Give the target app time to read the clipboard before we restore it.
        // Cmd+V events are already in the system event queue at this point, so 400 ms
        // is enough for even the slowest Electron apps to process the paste.
        try? await Task.sleep(for: .milliseconds(400))
        snapshot.restore()
        DiagnosticsLogger.log("Paste: clipboard restored")
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
    private static func injectViaAccessibility(text: String) -> Bool {
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

        if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            return true
        }

        var currentRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentRef)
        let current = (currentRef as? String) ?? ""
        let separator = current.isEmpty || current.hasSuffix(" ") || current.hasSuffix("\n") ? "" : " "
        return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, (current + separator + text) as CFTypeRef) == .success
    }
}
