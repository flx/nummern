import XCTest
@testable import Nummern

final class TableCellOverlayTests: XCTestCase {
    func testShouldCommitOnSelectionChangeForNonFormula() {
        XCTAssertTrue(TableCellOverlay.shouldCommitOnSelectionChange(editingText: "123"))
        XCTAssertTrue(TableCellOverlay.shouldCommitOnSelectionChange(editingText: "  text "))
        XCTAssertFalse(TableCellOverlay.shouldCommitOnSelectionChange(editingText: "=A0"))
    }
}
