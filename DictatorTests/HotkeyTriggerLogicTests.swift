import XCTest
@testable import Dictator

final class HotkeyTriggerLogicTests: XCTestCase {
    func testRightOptionTrigger() {
        let snap = HotkeyTriggerLogic.Snapshot(
            keyCode: 61,
            alternateDown: true,
            commandDown: false,
            key54Down: false,
            key58Down: false,
            key61Down: true
        )
        XCTAssertTrue(HotkeyTriggerLogic.isTriggerDown(preference: .rightOption, snap: snap))
        XCTAssertFalse(HotkeyTriggerLogic.isTriggerDown(preference: .leftOption, snap: snap))
    }

    func testEitherOptionAcceptsLeftOrRight() {
        let right = HotkeyTriggerLogic.Snapshot(
            keyCode: 61, alternateDown: true, commandDown: false,
            key54Down: false, key58Down: false, key61Down: true
        )
        let left = HotkeyTriggerLogic.Snapshot(
            keyCode: 58, alternateDown: true, commandDown: false,
            key54Down: false, key58Down: true, key61Down: false
        )
        XCTAssertTrue(HotkeyTriggerLogic.isTriggerDown(preference: .eitherOption, snap: right))
        XCTAssertTrue(HotkeyTriggerLogic.isTriggerDown(preference: .eitherOption, snap: left))
    }

    func testWrongModifierForRightOptionPreference() {
        let leftOnly = HotkeyTriggerLogic.Snapshot(
            keyCode: 58, alternateDown: true, commandDown: false,
            key54Down: false, key58Down: true, key61Down: false
        )
        XCTAssertTrue(HotkeyTriggerLogic.wrongModifierActive(
            preference: .rightOption,
            snap: leftOnly,
            sessionActive: false
        ))
    }
}
