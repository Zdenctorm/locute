import Foundation

enum TranscriptionSanitizer {
    /// Whisper na tichu/šumu často vrátí falešné „titulky“ — zahodíme jen známé halucinace.
    static func sanitized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = normalize(trimmed)
        guard normalized.count >= 3 else { return nil }

        if blockedExactNormalized.contains(normalized) {
            DiagnosticsLogger.log("Transcription dropped: known hallucination \"\(trimmed)\"")
            return nil
        }

        if isSubtitleHallucination(normalized) {
            DiagnosticsLogger.log("Transcription dropped: subtitle hallucination \"\(trimmed)\"")
            return nil
        }

        return trimmed
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSubtitleHallucination(_ normalized: String) -> Bool {
        let words = normalized.split(separator: " ")
        guard words.count <= 6 else { return false }

        if normalized.hasPrefix("titulky vytvoril") || normalized.hasPrefix("subtitles by") {
            return true
        }
        if normalized.contains("thanks for watching") || normalized.contains("thank you for watching") {
            return true
        }
        return false
    }

    private static let blockedExactNormalized: Set<String> = [
        "titulky vytvoril johnyx",
        "titulky vytvoril",
        "subtitles by johnyx",
        "subtitles created by johnyx",
        "dekuji za sledovani",
        "děkuji za sledování",
        "thanks for watching",
        "thank you for watching"
    ]
}

// MARK: - Vocabulary

/// Jeden záznam slovníku: kanonická forma + volitelné fonetické varianty.
/// `MyCompany: maj company, my company` → canonical="MyCompany", variants=["maj company", "my company"]
/// `KYC` (bez dvojtečky) → canonical="KYC", variants=[] (jde jen do promptu).
struct VocabularyEntry: Equatable, Sendable {
    let canonical: String
    let variants: [String]

    /// Parsuje jeden řádek do `VocabularyEntry?`. Prázdné/whitespace řádky → nil.
    static func parse(line: String) -> VocabularyEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("#") else { return nil } // poznámky

        if let colonIdx = trimmed.firstIndex(of: ":") {
            let canonical = trimmed[..<colonIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = trimmed[trimmed.index(after: colonIdx)...]
            let variants = rest
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !canonical.isEmpty else { return nil }
            return VocabularyEntry(canonical: canonical, variants: variants)
        } else {
            return VocabularyEntry(canonical: trimmed, variants: [])
        }
    }
}

/// Sada slovníkových záznamů + dvě transformace:
/// 1. `whisperPrompt` — string pro `DecodingOptions` (biasing dekodéru).
/// 2. `applyReplacements` — post-process variantního textu na kanonickou formu.
struct VocabularyDictionary: Sendable {
    let entries: [VocabularyEntry]

    static let empty = VocabularyDictionary(entries: [])

    init(entries: [VocabularyEntry]) {
        self.entries = entries
    }

    /// Parsuje volně psané řádky do entries. Tolerantní k prázdným řádkům a poznámkám.
    init(rawText: String) {
        self.entries = rawText
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .compactMap { VocabularyEntry.parse(line: String($0)) }
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Sestaví krátký prompt pro WhisperKit. Kanonika + první varianta (pokud je) — to dává
    /// dekodéru správný tvar i pár fonetických „nápověd". Limit ~200 znaků (≈ 100 tokenů),
    /// Whisper má prompt cap 224 tokenů.
    var whisperPrompt: String {
        guard !entries.isEmpty else { return "" }

        var pieces: [String] = []
        for entry in entries {
            pieces.append(entry.canonical)
            if let first = entry.variants.first {
                pieces.append(first)
            }
        }

        // Soft cap na ~200 znaků — defenzivní hranice, ať se vejdeme do 224 token limitu Whisperu.
        var prompt = ""
        for piece in pieces {
            let next = prompt.isEmpty ? piece : "\(prompt), \(piece)"
            if next.count > 200 { break }
            prompt = next
        }
        return prompt
    }

    /// Per-token varianta `applyReplacements`. Bere sekvenci `WordToken` (z `TranscriptionEngine`)
    /// a vrací novou sekvenci, kde tokeny odpovídající variantě jsou zfúzované do jednoho
    /// `WordToken` s kanonickou formou a vyplněným `originalText` (pro UI tooltip).
    ///
    /// Match je word-by-word case + diakritika insensitive. Vícevariantní matche (např. „any coin"
    /// → „Anycoin") konzumují víc tokenů, ale produkují jeden výsledný token s kanonickou formou.
    func applyReplacementsWithTracking(to words: [WordToken]) -> [WordToken] {
        guard !entries.isEmpty, !words.isEmpty else { return words }

        var result: [WordToken] = []
        var i = 0
        while i < words.count {
            var matched = false
            for entry in entries where !entry.variants.isEmpty {
                for variant in entry.variants {
                    let variantWords = variant
                        .split(whereSeparator: { $0.isWhitespace })
                        .map(String.init)
                    guard !variantWords.isEmpty,
                          i + variantWords.count <= words.count else { continue }

                    let slice = Array(words[i ..< (i + variantWords.count)])
                    guard VocabularyDictionary.wordsMatch(slice, variant: variantWords) else { continue }

                    let originalText = slice.map(\.text).joined(separator: " ")
                    let canonical = caseAdjustedCanonical(entry.canonical, original: originalText)
                    let avgConfidence = slice.map(\.confidence).reduce(0, +) / Float(slice.count)
                    result.append(WordToken(text: canonical, confidence: avgConfidence, originalText: originalText))
                    DiagnosticsLogger.log("Vocabulary: replaced \"\(originalText)\" → \"\(canonical)\"")
                    i += variantWords.count
                    matched = true
                    break
                }
                if matched { break }
            }
            if !matched {
                result.append(words[i])
                i += 1
            }
        }
        return result
    }

    private static func wordsMatch(_ candidate: [WordToken], variant: [String]) -> Bool {
        guard candidate.count == variant.count else { return false }
        for (token, variantWord) in zip(candidate, variant) {
            let normalizedToken = token.text
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .punctuationCharacters)
            let normalizedVariant = variantWord
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if normalizedToken != normalizedVariant { return false }
        }
        return true
    }

    /// Nahradí každou nalezenou variantu kanonickou formou. Word-boundary aware,
    /// case-insensitive, diakritika-insensitive na matching, výstup zachová kanoniku.
    func applyReplacements(to text: String) -> String {
        guard !entries.isEmpty, !text.isEmpty else { return text }

        var output = text
        for entry in entries {
            for variant in entry.variants {
                let before = output
                output = replaceVariant(variant, with: entry.canonical, in: output)
                if before != output {
                    DiagnosticsLogger.log("Vocabulary: replaced \"\(variant)\" → \"\(entry.canonical)\"")
                }
            }
        }
        return output
    }

    /// Diakritika-insensitive case-insensitive word-boundary replace.
    /// Hledáme přes znormalizovaný text (lowercase + bez diakritiky), ale slices vracíme
    /// z původního stringu — kanonický text dosazujeme tak jak ho zadal uživatel.
    private func replaceVariant(_ variant: String, with canonical: String, in source: String) -> String {
        let normalizedVariant = variant.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !normalizedVariant.isEmpty else { return source }

        // Sestavíme regex s flexibilním whitespace mezi slovy varianty (např. „any coin" matchne
        // i „any  coin" / „any\tcoin").
        let escaped = NSRegularExpression.escapedPattern(for: normalizedVariant)
        let flexibleWhitespace = escaped.replacingOccurrences(of: "\\ ", with: "\\s+")
        // Word boundary: před a po varianta nesmí navazovat písmeno/číslice.
        let pattern = "(?<![\\p{L}\\p{N}])\(flexibleWhitespace)(?![\\p{L}\\p{N}])"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return source
        }

        // Matchujeme proti znormalizovanému zdroji se zachováním stejné délky (folding zachovává
        // počet UTF-16 code units pro běžné znaky), takže rangy platí i pro originál.
        let normalizedSource = source.folding(options: .diacriticInsensitive, locale: .current)

        // Folding může změnit délku v exotických případech (ligatura → 2 znaky) — pak fallback.
        guard normalizedSource.utf16.count == source.utf16.count else {
            return source
        }

        let nsSource = normalizedSource as NSString
        let matches = regex.matches(in: normalizedSource, options: [], range: NSRange(location: 0, length: nsSource.length))
        guard !matches.isEmpty else { return source }

        // Aplikujeme od konce, ať se nepokazí pozice.
        let originalNS = source as NSString
        let mutable = NSMutableString(string: source)
        for match in matches.reversed() {
            mutable.replaceCharacters(in: match.range, with: caseAdjustedCanonical(canonical, original: originalNS.substring(with: match.range)))
        }
        return mutable as String
    }

    /// Pokud byla varianta v textu psaná celá velkými písmeny → kanonickou taky upcasujeme.
    /// Jinak vrátíme kanoniku tak jak ji uživatel zadal (preserves user-intended casing).
    private func caseAdjustedCanonical(_ canonical: String, original: String) -> String {
        let trimmed = original.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return canonical }
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return canonical }
        let allUpper = letters.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
        if allUpper && letters.count >= 2 {
            return canonical.uppercased()
        }
        return canonical
    }
}

/// Legacy UserDefaults klíč a výchozí seed — jen pro jednorázovou migraci do `LearningEngine`.
enum VocabularyStore {
    private static let legacyStorageKey = "vocabularyRawText"

    /// Výchozí seed pro migraci při prvním spuštění s `LearningEngine`.
    static let defaultSeedText: String = """
    # Slovník Locute — jeden termín na řádek.
    # „Kanonický: varianta1, varianta2" → po přepisu se varianty přepíšou na kanonický tvar.
    # Bez dvojtečky → termín jde jen do promptu Whisperu (biasing dekodéru).

    # Přidej svoje produktové termíny (domény, technické zkratky, vlastní jména, …):
    MyProduct: maj produkt, maj produktu, my product
    MyAppName: my app name, myappname
    KYC: kvajsí, kuajsí
    API: aj pí í
    PDF: pé dé ef, pe de ef
    HTML: ajčtímel, ej ti em el
    JSON: džejson
    REST: rest, rest api
    bitcoin
    ethereum: etherium, ethérium
    blockchain: blokčejn, blokčein
    přepis
    diktování
    board
    """

    /// Jednorázový zdroj pro `LearningEngine` při bootstrapu.
    static func legacyRawTextForMigration() -> String {
        let stored = UserDefaults.standard.string(forKey: legacyStorageKey) ?? ""
        return stored.isEmpty ? defaultSeedText : stored
    }

    /// Smaže staré UserDefaults klíče po úspěšné migraci do `LearningEngine`.
    static func clearLegacyStorage() {
        UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        UserDefaults.standard.removeObject(forKey: "vocabularySeeded.v1")
    }
}
