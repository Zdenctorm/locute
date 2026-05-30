import XCTest
@testable import Locute

final class TranscriptionSanitizerTests: XCTestCase {
    func testKeepsCzechSentence() {
        let text = "Dneska je krásné počasí venku na procházku"
        XCTAssertEqual(TranscriptionSanitizer.sanitized(text), text)
    }

    func testKeepsMinimalLegitimatePhrase() {
        XCTAssertEqual(TranscriptionSanitizer.sanitized("ab c"), "ab c")
    }

    func testDropVeryShortNormalized() {
        XCTAssertNil(TranscriptionSanitizer.sanitized("a"))
    }

    func testDropKnownJohnyHallucination() {
        XCTAssertNil(TranscriptionSanitizer.sanitized("titulky vytvořil Johnyx"))
    }

    func testSubtitlePrefixHallucinationsDropped() {
        XCTAssertNil(TranscriptionSanitizer.sanitized("Subtitles By Johnyx"))
    }
}
