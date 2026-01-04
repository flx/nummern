import XCTest
@testable import Nummern

final class CommandApplyTests: XCTestCase {
    func testAddSheetAndAddTable() {
        var project = ProjectModel()
        let addSheet = AddSheetCommand(name: "Sheet 1", sheetId: "sheet_1")
        let addTable = AddTableCommand(
            sheetId: "sheet_1",
            tableId: "table_1",
            name: "Table 1",
            rect: Rect(x: 10, y: 20, width: 300, height: 200),
            rows: 12,
            cols: 4,
            labels: LabelBands(topRows: 1, bottomRows: 0, leftCols: 1, rightCols: 0)
        )

        addSheet.apply(to: &project)
        addTable.apply(to: &project)

        XCTAssertEqual(project.sheets.count, 1)
        XCTAssertEqual(project.sheets[0].id, "sheet_1")
        XCTAssertEqual(project.sheets[0].tables.count, 1)
        XCTAssertEqual(project.sheets[0].tables[0].id, "table_1")
        XCTAssertEqual(project.sheets[0].tables[0].gridSpec.bodyRows, 12)
        XCTAssertEqual(project.sheets[0].tables[0].gridSpec.bodyCols, 4)
    }

    func testSetColumnTypeAppliesToTable() {
        let table = TableModel(
            id: "table_1",
            name: "Table",
            rect: Rect(x: 0, y: 0, width: 200, height: 120),
            rows: 4,
            cols: 3
        )
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        var project = ProjectModel(sheets: [sheet])

        let command = SetColumnTypeCommand(tableId: "table_1", col: 1, columnType: .currency)
        command.apply(to: &project)

        XCTAssertEqual(project.sheets[0].tables[0].bodyColumnTypes[1], .currency)
    }
}
