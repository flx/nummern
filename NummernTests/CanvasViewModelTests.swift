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
        let table = TableModel(id: "table_1", name: "Table", rect: Rect(x: 0, y: 0, width: 100, height: 80))
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        let viewModel = CanvasViewModel(project: ProjectModel(sheets: [sheet]))

        viewModel.resizeTable(tableId: "table_1", width: 240, height: 180)

        let updated = viewModel.project.sheets[0].tables[0].rect
        XCTAssertEqual(updated.width, 240)
        XCTAssertEqual(updated.height, 180)
    }
}
