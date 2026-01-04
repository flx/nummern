import XCTest
@testable import Nummern

final class UndoRedoTests: XCTestCase {
    func testUndoMoveTable() {
        let originalRect = Rect(x: 10, y: 20, width: 100, height: 80)
        let table = TableModel(id: "table_1", name: "table_1", rect: originalRect)
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        let viewModel = CanvasViewModel(project: ProjectModel(sheets: [sheet]))
        let undoManager = UndoManager()
        viewModel.setUndoManager(undoManager)

        viewModel.moveTable(tableId: "table_1", to: Rect(x: 50, y: 60, width: 100, height: 80))
        XCTAssertEqual(viewModel.project.sheets[0].tables[0].rect.x, 50)

        undoManager.undo()
        XCTAssertEqual(viewModel.project.sheets[0].tables[0].rect, originalRect)

        undoManager.redo()
        XCTAssertEqual(viewModel.project.sheets[0].tables[0].rect.x, 50)
    }

    func testUndoSetRangeClearsValues() {
        let table = TableModel(id: "table_1",
                               name: "table_1",
                               rect: Rect(x: 0, y: 0, width: 120, height: 80),
                               rows: 2,
                               cols: 2)
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        let viewModel = CanvasViewModel(project: ProjectModel(sheets: [sheet]))
        let undoManager = UndoManager()
        viewModel.setUndoManager(undoManager)

        viewModel.setRange(tableId: "table_1",
                           region: .body,
                           startRow: 0,
                           startCol: 0,
                           values: [[.number(1), .number(2)]])
        let key = RangeParser.address(region: .body, row: 0, col: 0)
        XCTAssertEqual(viewModel.project.sheets[0].tables[0].cellValues[key], .number(1))

        undoManager.undo()
        let updatedTable = viewModel.project.sheets[0].tables[0]
        XCTAssertEqual(updatedTable.cellValues[key], .empty)
        XCTAssertTrue(updatedTable.rangeValues.isEmpty)
    }
}
