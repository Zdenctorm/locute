import XCTest
@testable import Dictator

final class PostProcessingPreferenceTests: XCTestCase {

    private let enabledKey = "postProcessingEnabled"
    private let modelSizeKey = "postProcessingModelSize"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: modelSizeKey)
    }

    func testDefaultIsDisabled() {
        XCTAssertFalse(PostProcessingPreference.isEnabled)
    }

    func testTogglePersists() {
        PostProcessingPreference.isEnabled = true
        XCTAssertTrue(PostProcessingPreference.isEnabled)
        PostProcessingPreference.isEnabled = false
        XCTAssertFalse(PostProcessingPreference.isEnabled)
    }

    func testDefaultModelSizeIsStandard() {
        XCTAssertEqual(PostProcessingPreference.modelSize, .standard)
    }

    func testModelSizePersists() {
        PostProcessingPreference.modelSize = .compact
        XCTAssertEqual(PostProcessingPreference.modelSize, .compact)
    }

    func testStandardRepoIsQwen() {
        XCTAssertEqual(
            PostProcessingModelSize.standard.huggingFaceRepo,
            "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
        )
    }

    func testCompactRepoIsLlama() {
        XCTAssertEqual(
            PostProcessingModelSize.compact.huggingFaceRepo,
            "mlx-community/Llama-3.2-1B-Instruct-4bit"
        )
    }

    func testStandardLargerThanCompact() {
        XCTAssertGreaterThan(
            PostProcessingModelSize.standard.expectedDownloadBytes,
            PostProcessingModelSize.compact.expectedDownloadBytes
        )
    }

    func testNotificationFiresOnEnabledChange() {
        let expectation = XCTestExpectation(description: "notification fires")
        let observer = NotificationCenter.default.addObserver(
            forName: .dictatorPostProcessingPreferenceChanged,
            object: nil,
            queue: .main
        ) { _ in expectation.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }

        PostProcessingPreference.isEnabled = true
        wait(for: [expectation], timeout: 1)
    }

    func testNotificationFiresOnModelSizeChange() {
        let expectation = XCTestExpectation(description: "notification fires on model size change")
        let observer = NotificationCenter.default.addObserver(
            forName: .dictatorPostProcessingPreferenceChanged,
            object: nil,
            queue: .main
        ) { _ in expectation.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }

        PostProcessingPreference.modelSize = .compact
        wait(for: [expectation], timeout: 1)
    }
}
