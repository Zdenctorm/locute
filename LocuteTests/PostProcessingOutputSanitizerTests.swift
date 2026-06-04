import XCTest
@testable import Locute

final class PostProcessingOutputSanitizerTests: XCTestCase {
    func testReplacesEmDash() {
        let result = PostProcessingOutputSanitizer.replaceForbiddenDashes("ahoj — světe")
        XCTAssertFalse(result.contains("—"))
        XCTAssertTrue(result.contains(","))
    }

    func testStripsAssistantLeadIn() {
        let input = "posílám přílohu"
        let raw = "Samozřejmě, posílám přílohu."
        let cleaned = PostProcessingOutputSanitizer.cleaned(raw, originalInput: input)
        XCTAssertTrue(cleaned.lowercased().hasPrefix("posílám"))
    }

    func testDetectsAssistantReply() {
        XCTAssertTrue(
            PostProcessingOutputSanitizer.looksLikeAssistantReply(
                output: "Rád pomohu. Zde je váš text.",
                input: "dobrý den"
            )
        )
    }

    func testWordRetentionRejectsHallucination() {
        let input = "posílám přílohu dnes"
        let output = "Posílám přílohu dnes a rád vám také poradím s čímkoli dalším."
        let ratio = PostProcessingOutputSanitizer.wordRetentionRatio(output: output, input: input)
        XCTAssertGreaterThan(ratio, 0.5)
        let novel = PostProcessingOutputSanitizer.novelWordCount(output: output, input: input)
        XCTAssertGreaterThan(novel, 2)
    }
}
