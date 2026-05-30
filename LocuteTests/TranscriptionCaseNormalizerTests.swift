import XCTest
@testable import Locute

final class TranscriptionCaseNormalizerTests: XCTestCase {
    func testLowercasesSpuriousCaps() {
        let whitelist = TranscriptionCaseNormalizer.defaultWhitelist
        XCTAssertEqual(
            TranscriptionCaseNormalizer.normalize("Spusť ECHO server", whitelist: whitelist),
            "Spusť echo server"
        )
    }

    func testPreservesWhitelist() {
        let whitelist = TranscriptionCaseNormalizer.defaultWhitelist
        XCTAssertEqual(
            TranscriptionCaseNormalizer.normalize("Potřebujeme KYC a API", whitelist: whitelist),
            "Potřebujeme KYC a API"
        )
    }

    func testPreservesShortTokens() {
        let whitelist = TranscriptionCaseNormalizer.defaultWhitelist
        XCTAssertEqual(
            TranscriptionCaseNormalizer.normalize("OK tak", whitelist: whitelist),
            "OK tak"
        )
    }

    func testTrailingPunctuation() {
        let whitelist = TranscriptionCaseNormalizer.defaultWhitelist
        XCTAssertEqual(
            TranscriptionCaseNormalizer.normalize("ECHO, funguje", whitelist: whitelist),
            "echo, funguje"
        )
    }

    func testVocabularyWhitelistMerge() {
        let whitelist = TranscriptionCaseNormalizer.buildWhitelist(vocabularyCanonicals: ["MyProduct"])
        XCTAssertEqual(
            TranscriptionCaseNormalizer.normalize("MYPRODUCT je nový", whitelist: whitelist),
            "MYPRODUCT je nový"
        )
    }
}
