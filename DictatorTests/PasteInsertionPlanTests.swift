import XCTest
@testable import Dictator

final class PasteInsertionPlanTests: XCTestCase {
    func testOrderedSteps_CommandVPreferred() {
        XCTAssertEqual(PasteInsertionStep.ordered(prefersCommandVFirst: true), [.commandV, .accessibility])
    }

    func testOrderedSteps_AccessibilityPreferred() {
        XCTAssertEqual(PasteInsertionStep.ordered(prefersCommandVFirst: false), [.accessibility, .commandV])
    }

    func testSlackPreferCommandVByBundleID() {
        XCTAssertTrue(CommandVPastePreferringBundles.prefersCommandV(bundleID: "com.tinyspeck.slackmacgap"))
    }

    func testElectronSubstringsPreferCommandV() {
        XCTAssertTrue(CommandVPastePreferringBundles.prefersCommandV(bundleID: "com.example.electron.app"))
        XCTAssertFalse(CommandVPastePreferringBundles.prefersCommandV(bundleID: "com.apple.TextEdit"))
    }

    func testSafariListed() {
        XCTAssertTrue(CommandVPastePreferringBundles.prefersCommandV(bundleID: "com.apple.Safari"))
    }

    func testNilBundleNotCommandVPreferring() {
        XCTAssertFalse(CommandVPastePreferringBundles.prefersCommandV(bundleID: nil))
    }

    func testCursorBundlePrefersCommandV() {
        XCTAssertTrue(
            CommandVPastePreferringBundles.prefersCommandV(bundleID: "com.todesktop.230313mzl4w4u92")
        )
    }

    func testToDesktopPrefixPrefersCommandV() {
        XCTAssertTrue(CommandVPastePreferringBundles.prefersCommandV(bundleID: "com.todesktop.other-app-id"))
    }
}
