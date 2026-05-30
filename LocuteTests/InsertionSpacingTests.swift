import XCTest
@testable import Locute

final class InsertionSpacingTests: XCTestCase {
    func testNoPrefixWhenReplacingSelection() {
        let context = InsertionSpacing.Context(
            selectedText: "old",
            fullValue: "hello old world",
            selectedRange: NSRange(location: 6, length: 3)
        )
        XCTAssertEqual(
            InsertionSpacing.leadingPrefix(
                for: "new",
                context: context,
                replacingSelection: true,
                skipForTerminalPaste: false
            ),
            ""
        )
    }

    func testPrefixMidWord() {
        let context = InsertionSpacing.Context(
            selectedText: "",
            fullValue: "hello",
            selectedRange: NSRange(location: 5, length: 0)
        )
        XCTAssertEqual(
            InsertionSpacing.leadingPrefix(
                for: "world",
                context: context,
                replacingSelection: false,
                skipForTerminalPaste: false
            ),
            " "
        )
    }

    func testNoPrefixAfterSpace() {
        let context = InsertionSpacing.Context(
            selectedText: "",
            fullValue: "hello ",
            selectedRange: NSRange(location: 6, length: 0)
        )
        XCTAssertEqual(
            InsertionSpacing.leadingPrefix(
                for: "world",
                context: context,
                replacingSelection: false,
                skipForTerminalPaste: false
            ),
            ""
        )
    }

    func testNoPrefixAtStart() {
        let context = InsertionSpacing.Context(
            selectedText: "",
            fullValue: "",
            selectedRange: NSRange(location: 0, length: 0)
        )
        XCTAssertEqual(
            InsertionSpacing.leadingPrefix(
                for: "hello",
                context: context,
                replacingSelection: false,
                skipForTerminalPaste: false
            ),
            ""
        )
    }

    func testSkipForTerminal() {
        XCTAssertEqual(
            InsertionSpacing.leadingPrefix(
                for: "ls",
                context: nil,
                replacingSelection: false,
                skipForTerminalPaste: true
            ),
            ""
        )
    }

    func testNoPrefixWhenTextStartsWithSpace() {
        XCTAssertEqual(
            InsertionSpacing.leadingPrefix(
                for: " world",
                context: InsertionSpacing.Context(selectedText: nil, fullValue: "hi", selectedRange: NSRange(location: 2, length: 0)),
                replacingSelection: false,
                skipForTerminalPaste: false
            ),
            ""
        )
    }
}
