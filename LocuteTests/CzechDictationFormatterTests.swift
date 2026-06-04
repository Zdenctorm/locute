import XCTest
@testable import Locute

final class CzechDictationFormatterTests: XCTestCase {
    func testSpokenPeriodCommand() {
        let result = CzechDictationFormatter.format("ahoj tečka jak se máš", targetAppBundleID: nil)
        XCTAssertTrue(result.contains("Ahoj."))
    }

    func testCapitalizeAfterPeriod() {
        let result = CzechDictationFormatter.format("první věta. druhá věta", targetAppBundleID: nil)
        XCTAssertEqual(result, "První věta. Druhá věta")
    }

    func testNewParagraphCommand() {
        let result = CzechDictationFormatter.format("úvod nový odstavec tělo", targetAppBundleID: nil)
        XCTAssertTrue(result.contains("\n\n"))
    }

    func testEmailGreetingInMailContext() {
        let result = CzechDictationFormatter.format(
            "dobrý den posílám přílohu s pozdravem jan",
            targetAppBundleID: "com.apple.mail"
        )
        XCTAssertTrue(result.hasPrefix("Dobrý den,"))
        XCTAssertTrue(result.contains("\n\n"))
    }

    func testHeuristicCommaBeforeZe() {
        let result = CzechDictationFormatter.format(
            "myslím že to bude fungovat",
            targetAppBundleID: nil
        )
        XCTAssertTrue(result.contains("Myslím, že"))
    }

    func testHeuristicTerminalPeriod() {
        let result = CzechDictationFormatter.format(
            "posílám přílohu v příloze",
            targetAppBundleID: nil
        )
        XCTAssertTrue(result.hasSuffix("."))
    }

    func testHeuristicQuestionMark() {
        let result = CzechDictationFormatter.format(
            "jak to funguje",
            targetAppBundleID: nil
        )
        XCTAssertTrue(result.hasSuffix("?"))
    }

    func testEmailClosingParagraph() {
        let result = CzechDictationFormatter.format(
            "dobrý den posílám info děkuji jan novák",
            targetAppBundleID: "com.apple.mail"
        )
        XCTAssertTrue(result.localizedCaseInsensitiveContains("\n\nDěkuji"))
    }
}
