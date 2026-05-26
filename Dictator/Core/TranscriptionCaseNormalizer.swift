import Foundation

/// Fixes spurious ALL-CAPS tokens from Whisper while preserving acronyms and vocabulary canonical forms.
enum TranscriptionCaseNormalizer {
    static let defaultWhitelist: Set<String> = [
        "KYC", "AML", "SEPA", "EUR", "USD", "GBP", "CZK", "API", "HTTP", "HTTPS",
        "JSON", "XML", "SQL", "GPU", "CPU", "RAM", "SSD", "USB", "PDF", "CSV",
        "ID", "UUID", "URL", "DNS", "VPN", "SSH", "CLI", "GUI", "IDE", "PR",
        "HR", "CEO", "CTO", "CFO", "IPO", "ROI", "KPI", "OKR", "GDPR", "HIPAA",
        "EU", "USA", "UK", "IBAN", "SWIFT", "POS", "ATM", "PIN", "OTP", "2FA",
        "MFA", "JWT", "OAuth", "REST", "SOAP", "AWS", "GCP", "SDK", "CI", "CD",
        "QA", "UAT", "SLA", "ETA", "FAQ", "TBD", "ASAP", "FYI", "IMO", "AI", "ML",
        "LLM", "NLP", "STT", "TTS", "ANE", "M1", "M2", "M3", "M4", "OK",
    ]

    static func buildWhitelist(vocabularyCanonicals: [String]) -> Set<String> {
        var set = defaultWhitelist
        for term in vocabularyCanonicals {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let upper = trimmed.uppercased()
            if upper.contains(where: \.isLetter) {
                set.insert(upper)
            }
        }
        return set
    }

    static func normalize(_ text: String, whitelist: Set<String>) -> String {
        guard !text.isEmpty else { return text }
        let upperWhitelist = Set(whitelist.map { $0.uppercased() })
        var result = ""
        var word = ""

        func flushWord() {
            guard !word.isEmpty else { return }
            result += normalizeToken(word, whitelist: upperWhitelist)
            word = ""
        }

        for character in text {
            if character.isLetter || character.isNumber || character == "_" || character == "-" {
                word.append(character)
            } else {
                flushWord()
                result.append(character)
            }
        }
        flushWord()
        return result
    }

    private static func normalizeToken(_ token: String, whitelist: Set<String>) -> String {
        let (core, suffix) = splitTrailingPunctuation(token)
        guard !core.isEmpty else { return token }

        let coreUpper = core.uppercased()
        guard core.count >= 2,
              core == coreUpper,
              core.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              !whitelist.contains(coreUpper) else {
            return token
        }

        return core.lowercased() + suffix
    }

    private static func splitTrailingPunctuation(_ token: String) -> (String, String) {
        var core = token
        var suffix = ""
        while let last = core.last, !last.isLetter, !last.isNumber, last != Character("_") {
            suffix = String(last) + suffix
            core.removeLast()
        }
        return (core, suffix)
    }
}
