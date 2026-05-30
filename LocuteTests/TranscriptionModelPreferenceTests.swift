import XCTest
@testable import Locute

final class TranscriptionModelPreferenceTests: XCTestCase {
    func testSpeedVariantIsTurbo() {
        XCTAssertEqual(
            TranscriptionModelPreference.speed.whisperKitVariant,
            "large-v3-v20240930_turbo"
        )
    }

    func testAccuracyVariantIsV20240930() {
        XCTAssertEqual(
            TranscriptionModelPreference.accuracy.whisperKitVariant,
            "large-v3-v20240930"
        )
    }

    func testExpectedDownloadBytesOrder() {
        XCTAssertLessThan(
            TranscriptionModelPreference.speed.expectedDownloadBytes,
            ModelDownloadProgress.whisperLargeV3TotalBytes
        )
    }
}
