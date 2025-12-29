import XCTest
@testable import Nummern

final class LabelBandTests: XCTestCase {
    func testAdjustLabelBandCounts() {
        let table = TableModel(
            id: "table_1",
            name: "Table",
            rect: Rect(x: 0, y: 0, width: 200, height: 120)
        )
        let sheet = SheetModel(id: "sheet_1", name: "Sheet", tables: [table])
        var project = ProjectModel(sheets: [sheet])

        let updated = LabelBands(topRows: 2, bottomRows: 1, leftCols: 3, rightCols: 0)
        let command = SetLabelBandsCommand(tableId: "table_1", labelBands: updated)
        command.apply(to: &project)

        let stored = project.sheets[0].tables[0].gridSpec.labelBands
        XCTAssertEqual(stored.topRows, 2)
        XCTAssertEqual(stored.bottomRows, 1)
        XCTAssertEqual(stored.leftCols, 3)
        XCTAssertEqual(stored.rightCols, 0)
    }
}
