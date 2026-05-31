import XCTest
@testable import Nummern

final class ModelDecodingTests: XCTestCase {
    let json = """
    {"version":1,"sheets":[{"id":"sheet_1","name":"Tab1",
      "tables":[{"id":"table_1","name":"table_1",
        "rect":{"x":120.0,"y":120.0,"w":560.0,"h":120.0},
        "grid":{"rows":2,"cols":2,"labels":{"top":1,"left":0,"bottom":0,"right":0}},
        "columns":[{"index":0,"name":"A","dtype":"number","format":null},
                   {"index":1,"name":"B","dtype":"number","format":"currency"}],
        "body":[[1,2],[10,null]],
        "labels":{"top":[["A","B"]],"left":[],"bottom":[],"right":[]}}],
      "charts":[]}]}
    """

    func testDecodeProjectSnapshot() throws {
        let snapshot = try JSONDecoder().decode(ProjectSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.version, 1)
        let table = try XCTUnwrap(snapshot.table(id: "table_1"))
        XCTAssertEqual(table.grid.rows, 2)
        XCTAssertEqual(table.grid.labels.top, 1)
        XCTAssertEqual(table.cell(row: 0, col: 0), .number(1))
        XCTAssertEqual(table.cell(row: 1, col: 1), .empty)        // null
        XCTAssertEqual(table.columns[1].format, "currency")
        XCTAssertEqual(table.bandCell("top", row: 0, col: 1), .string("B"))
    }

    func testGridGeometryRegions() throws {
        let snapshot = try JSONDecoder().decode(ProjectSnapshot.self, from: Data(json.utf8))
        let table = try XCTUnwrap(snapshot.table(id: "table_1"))
        // gr=0 is the top label band, gr=1.. is body.
        XCTAssertEqual(GridGeometry.cell(table, gr: 0, gc: 0).region, .top)
        XCTAssertEqual(GridGeometry.cell(table, gr: 1, gc: 0).region, .body)
        XCTAssertEqual(GridGeometry.cell(table, gr: 1, gc: 0).value, .number(1))
    }

    func testCellValueDisplay() {
        XCTAssertEqual(CellValue.number(5).displayText(), "5")
        XCTAssertEqual(CellValue.number(2.5).displayText(), "2.5")
        XCTAssertEqual(CellValue.string("hi").displayText(), "hi")
        XCTAssertEqual(CellValue.empty.displayText(), "")
    }
}
