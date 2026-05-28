import Foundation

/// Offline Czech formatting: spacing, spoken punctuation commands, sentence caps, light email structure.
enum CzechDictationFormatter {
    static func format(_ text: String, targetAppBundleID: String?) -> String {
        var result = normalizeWhitespace(text)
        result = applySpokenCommands(result)
        result = collapsePunctuationSpacing(result)
        result = capitalizeSentences(result)
        result = applyEmailStructureIfNeeded(result, bundleID: targetAppBundleID)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: " ,", with: ",")
        s = s.replacingOccurrences(of: " .", with: ".")
        s = s.replacingOccurrences(of: " ?", with: "?")
        s = s.replacingOccurrences(of: " !", with: "!")
        s = s.replacingOccurrences(of: " :", with: ":")
        s = s.replacingOccurrences(of: " ;", with: ";")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func applySpokenCommands(_ text: String) -> String {
        var s = " \(text) "
        let replacements: [(String, String)] = [
            (" nový odstavec ", "\n\n"),
            (" novy odstavec ", "\n\n"),
            (" nový řádek ", "\n"),
            (" novy radek ", "\n"),
            (" tečka ", ". "),
            (" čárka ", ", "),
            (" carka ", ", "),
            (" otazník ", "? "),
            (" otaznik ", "? "),
            (" vykřičník ", "! "),
            (" vykricnik ", "! "),
            (" dvojtečka ", ": "),
            (" středník ", "; "),
            (" strednik ", "; "),
        ]
        for (spoken, symbol) in replacements {
            while let range = s.range(of: spoken, options: .caseInsensitive) {
                s.replaceSubrange(range, with: symbol)
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapsePunctuationSpacing(_ text: String) -> String {
        var s = text
        for punct in [".", ",", "?", "!", ":", ";"] {
            s = s.replacingOccurrences(of: " \(punct) ", with: "\(punct) ")
            s = s.replacingOccurrences(of: " \(punct)", with: punct)
        }
        return s
    }

    private static func capitalizeSentences(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = ""
        var capitalizeNext = true
        for char in text {
            if capitalizeNext, char.isLetter {
                result.append(String(char).uppercased())
                capitalizeNext = false
            } else {
                result.append(char)
                if ".!?".contains(char) || char == "\n" {
                    capitalizeNext = true
                }
            }
        }
        return result
    }

    private static func applyEmailStructureIfNeeded(_ text: String, bundleID: String?) -> String {
        let mailBundles: Set<String> = [
            "com.apple.mail",
            "com.microsoft.Outlook",
            "com.readdle.smartemail-Mac",
            "com.google.Gmail",
        ]
        let isMailContext = bundleID.map { mailBundles.contains($0) } ?? false
        let looksLikeEmail = text.localizedCaseInsensitiveContains("dobrý den")
            || text.localizedCaseInsensitiveContains("dobry den")
            || text.localizedCaseInsensitiveContains("vážen")
            || text.localizedCaseInsensitiveContains("s pozdravem")
        guard isMailContext || looksLikeEmail else { return text }

        var s = text
        let greetings = ["dobrý den", "dobry den", "ahoj", "vážen", "vážení"]
        for greeting in greetings {
            if let range = s.range(of: greeting, options: [.caseInsensitive, .anchored]) {
                let afterGreeting = s[range.upperBound...]
                if !afterGreeting.hasPrefix(",") && !afterGreeting.hasPrefix("\n") {
                    s.replaceSubrange(range, with: String(s[range]) + ",")
                }
                if !s.contains("\n\n"), s.count > greeting.count + 4 {
                    if let comma = s.firstIndex(of: ",") {
                        let insert = s.index(after: comma)
                        s.insert(contentsOf: "\n\n", at: insert)
                    }
                }
                break
            }
        }

        if s.localizedCaseInsensitiveContains("s pozdravem"), !s.contains("\n\nS pozdravem") {
            s = s.replacingOccurrences(
                of: "s pozdravem",
                with: "\n\nS pozdravem",
                options: .caseInsensitive
            )
        }
        return s
    }
}
