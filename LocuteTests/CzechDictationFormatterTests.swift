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
}
