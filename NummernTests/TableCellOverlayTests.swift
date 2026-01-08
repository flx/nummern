import XCTest
@testable import Nummern

final class TableCellOverlayTests: XCTestCase {
    func testTableRangeSelectionNormalization() {
        let range = TableRangeSelection(tableId: "table_1",
                                        region: .body,
                                        startRow: 3,
                                        startCol: 4,
                                        endRow: 1,
                                        endCol: 2)
        let normalized = range.normalized
        XCTAssertEqual(normalized.startRow, 1)
        XCTAssertEqual(normalized.endRow, 3)
        XCTAssertEqual(normalized.startCol, 2)
        XCTAssertEqual(normalized.endCol, 4)
        XCTAssertFalse(normalized.isSingleCell)
    }
}
