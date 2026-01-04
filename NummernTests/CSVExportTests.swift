import XCTest
@testable import Nummern

final class CSVExportTests: XCTestCase {
    func testExportMatchesSource() {
        let keyA0 = RangeParser.address(region: .body, row: 0, col: 0)
        let keyB0 = RangeParser.address(region: .body, row: 0, col: 1)
        let table = TableModel(id: "table_1",
                               name: "table_1",
                               rect: Rect(x: 0, y: 0, width: 120, height: 80),
                               rows: 1,
                               cols: 2,
                               cellValues: [keyA0: .string("a, b"), keyB0: .number(2)])
        let csv = CSVTableExporter.export(table: table)
        XCTAssertEqual(csv, "\"a, b\",2")
    }
}
