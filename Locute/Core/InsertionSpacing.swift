import Foundation

/// Decides whether to prepend a single space before dictated text at the insertion point.
enum InsertionSpacing {
    private static let enabledKey = "smartLeadingSpaceEnabled"

    static var isSmartLeadingSpaceEnabled: Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Context read from the focused accessibility element (when available).
    struct Context: Equatable, Sendable {
        var selectedText: String?
        var fullValue: String?
        var selectedRange: NSRange?
    }

    /// Leading space to prepend to dictated `text` before injection.
    static func leadingPrefix(
        for text: String,
        context: Context?,
        replacingSelection: Bool,
        skipForTerminalPaste: Bool
    ) -> String {
        guard isSmartLeadingSpaceEnabled, !skipForTerminalPaste else { return "" }
        guard !replacingSelection else { return "" }
        guard !text.isEmpty else { return "" }
        if text.first?.isWhitespace == true || text.hasPrefix("\n") {
            return ""
        }

        let before = characterBeforeInsertion(context: context)
        guard let before else {
            return ""
        }
        if before.isWhitespace {
            return ""
        }
        if ",.;:?!)]}\"'»«".contains(before) {
            return ""
        }
        return " "
    }

    static func characterBeforeInsertion(context: Context?) -> Character? {
        guard let context else { return nil }

        if let range = context.selectedRange,
           let value = context.fullValue,
           !value.isEmpty {
            let utf16 = value.utf16
            let location = range.location
            guard location > 0, location <= utf16.count else { return nil }
            let index = String.Index(utf16Offset: location - 1, in: value)
            return value[index]
        }

        if let selected = context.selectedText, !selected.isEmpty {
            return nil
        }

        if let value = context.fullValue, let last = value.last {
            return last
        }

        return nil
    }
}
