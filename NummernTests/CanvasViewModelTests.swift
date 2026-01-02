import XCTest
@testable import Nummern

final class CanvasViewModelTests: XCTestCase {
    func testMoveTableUpdatesModelAndLogsCommand() {
        let table = TableModel(id: "table_1", name: "Table", rect: Rect(x: 0, y: 0, width: 100, height: 80))
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        let viewModel = CanvasViewModel(project: ProjectModel(sheets: [sheet]))

        viewModel.moveTable(tableId: "table_1", to: Rect(x: 50, y: 60, width: 100, height: 80))

        let updated = viewModel.project.sheets[0].tables[0].rect
        XCTAssertEqual(updated.x, 50)
        XCTAssertEqual(updated.y, 60)
        XCTAssertTrue(viewModel.pythonLog.contains("set_rect"))
    }

    func testResizeTableUpdatesRect() {
        let labels = LabelBands(topRows: 1, bottomRows: 0, leftCols: 1, rightCols: 0)
        let table = TableModel(id: "table_1",
                               name: "table_1",
                               rect: Rect(x: 0, y: 0, width: 100, height: 80),
                               rows: 10,
                               cols: 6,
                               labelBands: labels)
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        let viewModel = CanvasViewModel(project: ProjectModel(sheets: [sheet]))

        viewModel.setBodySize(tableId: "table_1", rows: 8, cols: 4)

        let updatedTable = viewModel.project.sheets[0].tables[0]
        let metrics = TableGridMetrics(cellSize: CanvasGridSizing.cellSize,
                                       bodyRows: 8,
                                       bodyCols: 4,
                                       labelBands: labels)
        XCTAssertEqual(updatedTable.rect.width, Double(metrics.totalWidth))
        XCTAssertEqual(updatedTable.rect.height, Double(metrics.totalHeight))
    }

    func testReducingLabelBandsClearsInvalidSelection() {
        let labels = LabelBands(topRows: 2, bottomRows: 0, leftCols: 1, rightCols: 0)
        let table = TableModel(id: "table_1",
                               name: "Table",
                               rect: Rect(x: 0, y: 0, width: 100, height: 80),
                               rows: 10,
                               cols: 6,
                               labelBands: labels)
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        let viewModel = CanvasViewModel(project: ProjectModel(sheets: [sheet]))

        viewModel.selectCell(CellSelection(tableId: "table_1", region: .topLabels, row: 1, col: 0))
        XCTAssertNotNil(viewModel.selectedCell)

        viewModel.setLabelBands(tableId: "table_1",
                                labelBands: LabelBands(topRows: 1, bottomRows: 0, leftCols: 1, rightCols: 0))

        XCTAssertNil(viewModel.selectedCell)
    }

    func testLabelCellFormulaIsStoredAsFormula() {
        let labels = LabelBands(topRows: 0, bottomRows: 1, leftCols: 0, rightCols: 0)
        let table = TableModel(id: "table_1",
                               name: "table_1",
                               rect: Rect(x: 0, y: 0, width: 100, height: 80),
                               rows: 5,
                               cols: 4,
                               labelBands: labels)
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        let viewModel = CanvasViewModel(project: ProjectModel(sheets: [sheet]))

        viewModel.setCellValue(tableId: "table_1",
                               region: .bottomLabels,
                               row: 0,
                               col: 0,
                               rawValue: "=SUM(A1:A2)")

        let updatedTable = viewModel.project.sheets[0].tables[0]
        let key = RangeParser.address(region: .bottomLabels, row: 0, col: 0)
        XCTAssertEqual(updatedTable.formulas[key]?.formula, "=SUM(A1:A2)")
        XCTAssertNil(updatedTable.cellValues[key])
    }
}
