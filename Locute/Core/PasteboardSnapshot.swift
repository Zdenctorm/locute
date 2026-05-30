import Cocoa

/// Captures `NSPasteboard.general` before Locute overwrites it for Cmd+V injection.
struct PasteboardSnapshot: Sendable {
    private let items: [(NSPasteboard.PasteboardType, Data)]
    private let changeCountAtCapture: Int

    private init(items: [(NSPasteboard.PasteboardType, Data)], changeCountAtCapture: Int) {
        self.items = items
        self.changeCountAtCapture = changeCountAtCapture
    }

    @MainActor
    static func capture(from pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        var captured: [(NSPasteboard.PasteboardType, Data)] = []
        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                captured.append((type, data))
            }
        }
        return PasteboardSnapshot(items: captured, changeCountAtCapture: pasteboard.changeCount)
    }

    /// Restores captured items if the pasteboard was not changed by the user after our capture.
    ///
    /// - Parameter maxChangeCount: Upper bound on `pasteboard.changeCount` to still treat as "only Locute touched it".
    @MainActor
    @discardableResult
    func restore(to pasteboard: NSPasteboard = .general, maxChangeCount: Int) -> Bool {
        guard pasteboard.changeCount <= maxChangeCount else {
            DiagnosticsLogger.log(
                "Paste: clipboard restore skipped (changeCount=\(pasteboard.changeCount) > max=\(maxChangeCount))"
            )
            return false
        }

        guard !items.isEmpty else {
            if pasteboard.changeCount <= maxChangeCount {
                pasteboard.clearContents()
                DiagnosticsLogger.log("Paste: clipboard cleared (was empty at capture)")
                return true
            }
            return false
        }

        pasteboard.clearContents()
        for (type, data) in items {
            pasteboard.setData(data, forType: type)
        }
        DiagnosticsLogger.log("Paste: clipboard restored (\(items.count) type(s))")
        return true
    }

    /// After capture, Locute typically performs `clearContents` + `setString` (+ optional reads).
    var maxChangeCountAfterOurWrites: Int {
        changeCountAtCapture + 4
    }
}
