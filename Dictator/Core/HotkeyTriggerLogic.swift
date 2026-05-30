import Foundation

/// Pure hotkey trigger evaluation — testable without CGEvent.
enum HotkeyTriggerLogic {
    struct Snapshot: Equatable, Sendable {
        let keyCode: Int
        let alternateDown: Bool
        let commandDown: Bool
        let key54Down: Bool
        let key58Down: Bool
        let key61Down: Bool

        static let leftOptionKeyCode = 58
        static let rightOptionKeyCode = 61
        static let rightCommandKeyCode = 54
    }

    static func isTriggerDown(preference: HotkeyChoice, snap: Snapshot) -> Bool {
        switch preference {
        case .eitherOption:
            return snap.alternateDown && (
                snap.key58Down
                    || snap.key61Down
                    || snap.keyCode == Snapshot.leftOptionKeyCode
                    || snap.keyCode == Snapshot.rightOptionKeyCode
            )
        case .rightOption:
            return snap.alternateDown && (snap.key61Down || snap.keyCode == Snapshot.rightOptionKeyCode)
        case .leftOption:
            return snap.alternateDown && (snap.key58Down || snap.keyCode == Snapshot.leftOptionKeyCode)
        case .rightCommand:
            return snap.commandDown && (snap.key54Down || snap.keyCode == Snapshot.rightCommandKeyCode)
        }
    }

    static func wrongModifierActive(preference: HotkeyChoice, snap: Snapshot, sessionActive: Bool) -> Bool {
        guard !sessionActive else { return false }
        switch preference {
        case .eitherOption:
            return false
        case .rightOption:
            return snap.alternateDown && snap.key58Down && !snap.key61Down
        case .leftOption:
            return snap.alternateDown && snap.key61Down && !snap.key58Down
        case .rightCommand:
            return snap.alternateDown && (snap.key58Down || snap.key61Down)
        }
    }
}
