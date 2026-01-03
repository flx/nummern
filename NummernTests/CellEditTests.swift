import XCTest
@testable import Nummern

final class CellEditTests: XCTestCase {
    func testSetRangePopulatesCellValues() {
        let table = TableModel(
            id: "table_1",
            name: "Table",
            rect: Rect(x: 0, y: 0, width: 200, height: 120),
            rows: 3,
            cols: 3
        )
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        var project = ProjectModel(sheets: [sheet])

        let values: [[CellValue]] = [
            [.number(1), .number(2)],
            [.string("A"), .empty]
        ]
        let command = SetRangeCommand(tableId: "table_1", range: "body[A0:B1]", values: values)
        command.apply(to: &project)

        let cells = project.sheets[0].tables[0].cellValues
        XCTAssertEqual(cells["body[A0]"], .number(1))
        XCTAssertEqual(cells["body[B0]"], .number(2))
        XCTAssertEqual(cells["body[A1]"], .string("A"))
        XCTAssertEqual(cells["body[B1]"], .empty)
    }
}
