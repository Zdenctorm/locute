import Foundation

/// Offline Czech punctuation heuristics when Whisper (and optionally LLM) leave continuous prose.
enum CzechHeuristicPunctuator {
    private static let subordinateCommaTriggers = CzechPunctuationRules.commaBeforeSubordinators
    private static let sentenceBreakTriggers = CzechPunctuationRules.periodBeforeConjunctions + ["proto"]
    private static let questionSentenceStarters = CzechPunctuationRules.questionStarters
    private static let questionPhrases = CzechPunctuationRules.questionPhrases + [
        "je to tak", "že ne", "nebo ne", "viď", "vid",
    ]
    private static let maxWordsWithoutPunctuation = CzechPunctuationRules.maxWordsWithoutPunctuation
    private static let minWordsForSentenceBreak = CzechPunctuationRules.minWordsBeforeClauseBreak

    static func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        if isWellPunctuated(text) { return collapsePunctuationSpacing(text) }

        var result = text
        result = insertCommasBeforeSubordinateClauses(result)
        result = insertSentenceBreaks(result)
        result = breakOverlongClauses(result)
        result = applyTerminalPunctuationToSentences(result)
        result = PostProcessingOutputSanitizer.replaceForbiddenDashes(result)
        return collapsePunctuationSpacing(result)
    }

    /// True when long text still lacks real sentence punctuation (e.g. LLM returned one block).
    static func needsMorePunctuation(_ text: String) -> Bool {
        let words = wordCount(text)
        guard words >= 8 else { return false }
        return punctuationDensity(in: text) < 0.07
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
            output = (output as NSString).replacingCharacters(in: match.range, with: ", \(word) ")
        }
        return output
    }

    // MARK: - Sentence breaks

    private static func insertSentenceBreaks(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count >= minWordsForSentenceBreak + 2 else { return text }

        var result = ""
        var wordsSinceBreak = 0
        for (index, rawWord) in words.enumerated() {
            let word = String(rawWord)
            let normalized = normalizedToken(word)

            if index > 0 {
                if shouldBreakBefore(word: normalized, wordsSinceBreak: wordsSinceBreak, previousChunk: result) {
                    appendSentenceEnd(to: &result, for: result)
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
        guard wordsSinceBreak >= minWordsForSentenceBreak else { return false }
        guard sentenceBreakTriggers.contains(word) else { return false }
        let tail = previousChunk.suffix(32)
        if tail.contains(".") || tail.contains("?") || tail.contains("!") { return false }
        if tail.hasSuffix(",") { return false }
        return true
    }

    // MARK: - Long clauses

    private static func breakOverlongClauses(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count > maxWordsWithoutPunctuation else { return text }

        var result = ""
        var sincePunct = 0
        for (index, raw) in words.enumerated() {
            let word = String(raw)
            let norm = normalizedToken(word)
            if index > 0 {
                if sincePunct >= maxWordsWithoutPunctuation,
                   sentenceBreakTriggers.contains(norm) || ["proto", "tedy", "totiž", "totiz"].contains(norm) {
                    appendSentenceEnd(to: &result, for: result)
                    sincePunct = 0
                } else if sincePunct >= maxWordsWithoutPunctuation + 3 {
                    appendSentenceEnd(to: &result, for: result)
                    sincePunct = 0
                }
                result.append(" ")
            }
            result.append(word)
            if let last = word.last, ".!?".contains(last) {
                sincePunct = 0
            } else {
                sincePunct += 1
            }
        }
        return result
    }

    // MARK: - Terminal punctuation per sentence

    private static func applyTerminalPunctuationToSentences(_ text: String) -> String {
        var result = ""
        var buffer = ""

        func flushBuffer() {
            let trimmed = buffer.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { buffer = ""; return }
            result.append(punctuatedSentence(trimmed))
            buffer = ""
        }

        for char in text {
            if char == "\n" {
                flushBuffer()
                result.append("\n")
            } else if ".!?".contains(char) {
                buffer.append(char)
                flushBuffer()
            } else {
                buffer.append(char)
            }
        }
        flushBuffer()
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func punctuatedSentence(_ sentence: String) -> String {
        var s = sentence.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return "" }

        if let last = s.last, ".!?".contains(last) {
            if last == "?" || last == "!" { return s }
            if last == ".", isQuestionSentence(s.dropLast()) {
                return String(s.dropLast()) + "?"
            }
            return s
        }

        if isQuestionSentence(s) {
            s.append("?")
        } else {
            s.append(".")
        }
        return s
    }

    private static func appendSentenceEnd(to result: inout String, for sentenceSoFar: String) {
        let trimmed = sentenceSoFar.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if trimmed.hasSuffix("?") || trimmed.hasSuffix("!") || trimmed.hasSuffix(".") { return }
        result.append(isQuestionSentence(trimmed) ? "?" : ".")
    }

    // MARK: - Czech questions

    private static func isQuestionSentence(_ sentence: Substring) -> Bool {
        isQuestionSentence(String(sentence))
    }

    private static func isQuestionSentence(_ sentence: String) -> Bool {
        let normalized = sentence
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        let words = normalized.split(separator: " ").map(String.init)
        guard let first = words.first else { return false }

        if questionSentenceStarters.contains(first) { return true }

        for phrase in questionPhrases where normalized.contains(phrase) {
            return true
        }

        if normalized.contains(" prosím ") || normalized.hasSuffix(" prosím")
            || normalized.contains(" prosim ") || normalized.hasSuffix(" prosim") {
            return true
        }

        if normalized.contains(" jestli ") || normalized.contains(" zda ") {
            if words.count <= 14 { return true }
            if normalized.hasPrefix("nevím") || normalized.hasPrefix("nevim")
                || normalized.hasPrefix("ptám") || normalized.hasPrefix("ptam")
                || normalized.contains("zeptal") || normalized.contains("zeptala")
                || normalized.contains("říkám si") || normalized.contains("rikam si") {
                return true
            }
        }

        if words.count <= 10,
           ["muzete", "muzes", "mate", "mas", "ma", "mame", "jsou", "je", "bude", "budou"].contains(first) {
            return true
        }

        if words.count >= 2, words[1] == "se", ["jak", "kde", "kdy", "proc", "co"].contains(first) {
            return true
        }

        if normalized.contains(" jak se ") || normalized.contains(" jak ti ")
            || normalized.contains(" jak vam ") || normalized.contains(" jak vám ") {
            return true
        }

        return false
    }

    // MARK: - Helpers

    private static func isWellPunctuated(_ text: String) -> Bool {
        let words = wordCount(text)
        guard words > 0 else { return true }
        let density = punctuationDensity(in: text)
        if words >= 20 { return density >= 0.09 }
        return density >= 0.14
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    private static func normalizedToken(_ word: String) -> String {
        word
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs"))
            .trimmingCharacters(in: .punctuationCharacters)
    }

    private static func punctuationDensity(in text: String) -> Double {
        let words = wordCount(text)
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
        s = s.replacingOccurrences(of: "?.", with: "?")
        s = s.replacingOccurrences(of: ".?", with: "?")
        return s
    }
}
