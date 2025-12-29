import XCTest
@testable import Nummern

final class TypeInferenceTests: XCTestCase {
    func testColumnPromotesToStringOnText() {
        let table = TableModel(
            id: "table_1",
            name: "Table",
            rect: Rect(x: 0, y: 0, width: 200, height: 120),
            rows: 5,
            cols: 2
        )
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        var project = ProjectModel(sheets: [sheet])

        let numeric = SetCellsCommand(tableId: "table_1", cellMap: ["body[A1]": .number(3)])
        numeric.apply(to: &project)
        XCTAssertEqual(project.sheets[0].tables[0].bodyColumnTypes[0], .number)

        let text = SetCellsCommand(tableId: "table_1", cellMap: ["body[A2]": .string("Note")])
        text.apply(to: &project)
        XCTAssertEqual(project.sheets[0].tables[0].bodyColumnTypes[0], .string)
    }
}
