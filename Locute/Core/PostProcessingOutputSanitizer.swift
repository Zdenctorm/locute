import Foundation

/// Vyčištění výstupu lokálního LLM — žádné odpovědi asistenta, žádné pomlčky.
enum PostProcessingOutputSanitizer {
    private static let assistantLeadInPrefixes = [
        "samozřejmě", "jasně", "ano", "ne", "dobře", "rozumím",
        "ráda pomohu", "rád pomohu", "rada pomohu", "rad pomohu",
        "zde je", "tady je", "zde naleznete", "tady máte",
        "doufám", "neni problem", "není problém", "prepisu", "přepisu",
        "upraveny text", "upravený text", "zde upraveny", "zde upravený",
        "výsledek", "odpověď", "odpoved",
    ]

    static func cleaned(_ raw: String, originalInput: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = stripWrappingQuotes(text)
        text = extractEmbeddedTranscriptIfPresent(text, fallback: text)
        text = replaceForbiddenDashes(text)
        text = stripAssistantLeadIn(text, originalInput: originalInput)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func replaceForbiddenDashes(_ text: String) -> String {
        var result = text
        for dash in CzechPunctuationRules.forbiddenDashes {
            result = result.replacingOccurrences(of: dash, with: ", ")
        }
        while result.contains(", ,") {
            result = result.replacingOccurrences(of: ", ,", with: ", ")
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result
    }

    static func looksLikeAssistantReply(output: String, input: String) -> Bool {
        let out = folded(output)
        let inp = folded(input)
        for prefix in assistantLeadInPrefixes where out.hasPrefix(prefix) {
            if !inp.hasPrefix(prefix) { return true }
        }
        let markers = [" jako ai ", " jsem ai ", " jsem jazykovy model ", " jsem jazykový model "]
        for marker in markers where out.contains(marker) {
            return true
        }
        return false
    }

    /// Podíl slov z přepisu, která musí v přežít ve výstupu (po normalizaci).
    static func wordRetentionRatio(output: String, input: String) -> Double {
        let inputTokens = tokenSet(input)
        guard !inputTokens.isEmpty else { return 1 }
        let outputTokens = tokenSet(output)
        let kept = inputTokens.intersection(outputTokens).count
        return Double(kept) / Double(inputTokens.count)
    }

    /// Kolik nových slov výstup přidal oproti přepisu.
    static func novelWordCount(output: String, input: String) -> Int {
        let inputTokens = tokenSet(input)
        let outputTokens = tokenList(output)
        return outputTokens.filter { !inputTokens.contains($0) }.count
    }

    // MARK: - Private

    private static func stripWrappingQuotes(_ text: String) -> String {
        var s = text
        let pairs: [(String, String)] = [
            ("\"", "\""), ("„", "\""), ("“", "\""), ("'", "'"),
        ]
        for (open, close) in pairs {
            if s.hasPrefix(open), s.hasSuffix(close), s.count > open.count + close.count {
                s = String(s.dropFirst(open.count).dropLast(close.count))
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractEmbeddedTranscriptIfPresent(_ text: String, fallback: String) -> String {
        if let range = text.range(of: "[PŘEPIS K ÚPRAVĚ]", options: .caseInsensitive),
           let end = text.range(of: "[KONEC PŘEPISU]", options: .caseInsensitive),
           range.upperBound < end.lowerBound {
            return String(text[range.upperBound ..< end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fallback
    }

    private static func stripAssistantLeadIn(_ output: String, originalInput: String) -> String {
        var result = output
        let outFolded = folded(output)
        let inFolded = folded(originalInput)
        for prefix in assistantLeadInPrefixes {
            guard outFolded.hasPrefix(prefix), !inFolded.hasPrefix(prefix) else { continue }
            if let range = result.range(of: prefix, options: [.caseInsensitive, .anchored]) {
                result = String(result[range.upperBound...])
                result = result.trimmingCharacters(in: CharacterSet(charactersIn: ",:;.!?\n "))
            }
        }
        return result
    }

    private static func tokenSet(_ text: String) -> Set<String> {
        Set(tokenList(text))
    }

    private static func tokenList(_ text: String) -> [String] {
        folded(text)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs"))
    }
}
