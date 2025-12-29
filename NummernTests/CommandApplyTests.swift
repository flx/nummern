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
}
