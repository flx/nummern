import XCTest
@testable import Nummern

final class TableModelTests: XCTestCase {
    func testGridSpecDefaults() {
        let table = TableModel(name: "Table", rect: Rect(x: 0, y: 0, width: 10, height: 10))

        XCTAssertEqual(table.gridSpec.bodyRows, 10)
        XCTAssertEqual(table.gridSpec.bodyCols, 6)
        XCTAssertEqual(table.gridSpec.labelBands, .zero)
    }

    func testRectMutation() {
        var table = TableModel(name: "Table", rect: Rect(x: 0, y: 0, width: 10, height: 10))
        let updated = Rect(x: 12, y: 34, width: 56, height: 78)

        table.rect = updated

        XCTAssertEqual(table.rect, updated)
    }
}
