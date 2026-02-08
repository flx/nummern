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

    func testAddChartAppliesToSheet() {
        let table = TableModel(
            id: "table_1",
            name: "Table",
            rect: Rect(x: 0, y: 0, width: 200, height: 120),
            rows: 4,
            cols: 3
        )
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        var project = ProjectModel(sheets: [sheet])

        let command = AddChartCommand(sheetId: "sheet_1",
                                      chartId: "chart_1",
                                      name: "chart_1",
                                      rect: Rect(x: 10, y: 20, width: 240, height: 180),
                                      chartType: .line,
                                      tableId: "table_1",
                                      valueRange: "body[A0:A3]")
        command.apply(to: &project)

        XCTAssertEqual(project.sheets[0].charts.count, 1)
        XCTAssertEqual(project.sheets[0].charts[0].id, "chart_1")
        XCTAssertEqual(project.sheets[0].charts[0].tableId, "table_1")
    }

    func testSetRangeClearsOverlappingFormula() {
        let table = TableModel(
            id: "table_1",
            name: "Table",
            rect: Rect(x: 0, y: 0, width: 200, height: 120),
            rows: 2,
            cols: 2,
            formulas: ["body[A0]": FormulaSpec(formula: "=1+1", mode: .spreadsheet)]
        )
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        var project = ProjectModel(sheets: [sheet])

        let command = SetRangeCommand(tableId: "table_1",
                                      range: "body[A0:A0]",
                                      values: [[.number(5)]])
        command.apply(to: &project)

        let updated = project.sheets[0].tables[0]
        XCTAssertNil(updated.formulas["body[A0]"])
        XCTAssertEqual(updated.cellValues["body[A0]"], .number(5))
    }

    func testSetCellsClearsOverlappingFormulaRange() {
        let table = TableModel(
            id: "table_1",
            name: "Table",
            rect: Rect(x: 0, y: 0, width: 200, height: 120),
            rows: 2,
            cols: 2,
            formulas: ["body[A0:B0]": FormulaSpec(formula: "=A0+1", mode: .spreadsheet)]
        )
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        var project = ProjectModel(sheets: [sheet])

        let command = SetCellsCommand(tableId: "table_1",
                                      cellMap: ["body[B0]": .number(9)])
        command.apply(to: &project)

        let updated = project.sheets[0].tables[0]
        XCTAssertNil(updated.formulas["body[A0:B0]"])
        XCTAssertEqual(updated.cellValues["body[B0]"], .number(9))
    }

    func testSetRangePadsRaggedRowsToRectangle() {
        let table = TableModel(
            id: "table_1",
            name: "Table",
            rect: Rect(x: 0, y: 0, width: 200, height: 120),
            rows: 3,
            cols: 3
        )
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        var project = ProjectModel(sheets: [sheet])

        let command = SetRangeCommand(tableId: "table_1",
                                      range: "body[A0:B1]",
                                      values: [[.number(1)], [.number(2), .number(3)]])
        command.apply(to: &project)

        let updated = project.sheets[0].tables[0]
        XCTAssertEqual(updated.cellValues["body[A0]"], .number(1))
        XCTAssertEqual(updated.cellValues["body[B0]"], .empty)
        XCTAssertEqual(updated.cellValues["body[A1]"], .number(2))
        XCTAssertEqual(updated.cellValues["body[B1]"], .number(3))
        XCTAssertEqual(updated.rangeValues["body[A0:B1]"]?.values.count, 2)
        XCTAssertEqual(updated.rangeValues["body[A0:B1]"]?.values.first?.count, 2)
    }
}
