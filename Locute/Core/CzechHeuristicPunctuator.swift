import Foundation

/// Offline Czech punctuation heuristics when Whisper (and optionally LLM) leave continuous prose.
enum CzechHeuristicPunctuator {
    private static let subordinateCommaTriggers = [
        "že", "když", "protože", "pokud", "jestliže", "aby", "než",
        "který", "která", "které", "kteří", "kde",
    ]

    private static let sentenceBreakTriggers = [
        "ale", "avšak", "proto", "takže", "potom", "pak", "navíc",
        "nicméně", "ovšem", "přesto", "zároveň", "nakonec",
    ]

    private static let questionStarters = [
        "jak", "proč", "kde", "kdy", "kolik", "co", "kdo", "čí",
        "můžeš", "můžete", "je", "jsou", "má", "máte", "bude", "budou",
    ]

    static func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        if punctuationDensity(in: text) >= 0.12 { return text }

        var result = text
        result = insertCommasBeforeSubordinateClauses(result)
        result = insertSentenceBreaks(result)
        result = applyTerminalPunctuation(result)
        return collapsePunctuationSpacing(result)
    }

    // MARK: - Commas

    private static func insertCommasBeforeSubordinateClauses(_ text: String) -> String {
        var result = text
        for word in subordinateCommaTriggers {
            result = insertCommaBefore(word: word, in: result)
        }
        return result
    }

    private static func insertCommaBefore(word: String, in text: String) -> String {
        let pattern = "(?<![\\p{L}\\p{N},.!?;:])\\s+\(NSRegularExpression.escapedPattern(for: word))\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            let range = match.range
            let replacement = ", \(word) "
            output = (output as NSString).replacingCharacters(in: range, with: replacement)
        }
        return output
    }

    // MARK: - Sentence breaks

    private static func insertSentenceBreaks(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count >= 10 else { return text }

        var result = ""
        var wordsSinceBreak = 0
        for (index, rawWord) in words.enumerated() {
            let word = String(rawWord)
            let normalized = word
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs"))
                .trimmingCharacters(in: .punctuationCharacters)

            if index > 0 {
                if shouldBreakBefore(word: normalized, wordsSinceBreak: wordsSinceBreak, previousChunk: result) {
                    if !result.hasSuffix(".") && !result.hasSuffix("?") && !result.hasSuffix("!") {
                        result.append(".")
                    }
                    wordsSinceBreak = 0
                }
                result.append(" ")
            }
            result.append(word)
            wordsSinceBreak += 1
        }
        return result
    }

    private static func shouldBreakBefore(
        word: String,
        wordsSinceBreak: Int,
        previousChunk: String
    ) -> Bool {
        guard wordsSinceBreak >= 6 else { return false }
        guard sentenceBreakTriggers.contains(word) else { return false }
        let tail = previousChunk.suffix(24)
        if tail.contains(".") || tail.contains("?") || tail.contains("!") { return false }
        if tail.hasSuffix(",") { return false }
        return true
    }

    // MARK: - Terminal punctuation

    private static func applyTerminalPunctuation(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        let last = result.last!
        if ".!?".contains(last) { return result }

        if looksLikeQuestion(result) {
            result.append("?")
        } else {
            result.append(".")
        }
        return result
    }

    private static func looksLikeQuestion(_ text: String) -> Bool {
        let firstWord = text
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map { String($0) }
            .map {
                $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs"))
                    .trimmingCharacters(in: .punctuationCharacters)
            } ?? ""
        if questionStarters.contains(firstWord) { return true }

        let lowered = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "cs")).lowercased()
        return lowered.contains(" prosím ") || lowered.hasSuffix(" prosím")
            || lowered.contains(" že ano") || lowered.contains(" ze ano")
    }

    // MARK: - Helpers

    private static func punctuationDensity(in text: String) -> Double {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        guard words > 0 else { return 0 }
        let punctCount = text.filter { ".!?,:;".contains($0) }.count
        return Double(punctCount) / Double(words)
    }

    private static func collapsePunctuationSpacing(_ text: String) -> String {
        var s = text
        for punct in [".", ",", "?", "!", ":", ";"] {
            s = s.replacingOccurrences(of: " \(punct) ", with: "\(punct) ")
            s = s.replacingOccurrences(of: " \(punct)", with: punct)
        }
        s = s.replacingOccurrences(of: "..", with: ".")
        s = s.replacingOccurrences(of: ",,", with: ",")
        return s
    }
}
