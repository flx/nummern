import XCTest
@testable import Nummern

final class GridVirtualizationTests: XCTestCase {
    // cellHeight = 24, cellWidth = 80

    func testVisibleRowsWindow() {
        // A viewport from y=50 to y=150 covers rows 2..6 (rounded out).
        let rows = GridGeometry.visibleRows(in: CGRect(x: 0, y: 50, width: 100, height: 100),
                                            totalRows: 100)
        XCTAssertEqual(rows, 2..<7)
    }

    func testVisibleRowsClampToTotal() {
        let rows = GridGeometry.visibleRows(in: CGRect(x: 0, y: 0, width: 80, height: 10_000),
                                            totalRows: 5)
        XCTAssertEqual(rows, 0..<5)
    }

    func testVisibleColsWindow() {
        // x=10..170 with cellWidth 80 -> cols 0..3 (rounded out: floor(10/80)=0, ceil(170/80)=3)
        let cols = GridGeometry.visibleCols(in: CGRect(x: 10, y: 0, width: 160, height: 24),
                                            totalCols: 50)
        XCTAssertEqual(cols, 0..<3)
    }

    func testEmptyRectIsEmptyRange() {
        XCTAssertEqual(GridGeometry.visibleRows(in: .zero, totalRows: 100), 0..<0)
        XCTAssertEqual(GridGeometry.visibleCols(in: CGRect(x: 0, y: 0, width: 0, height: 24),
                                                totalCols: 10), 0..<0)
    }

    func testGridSizeMatchesGridFootprint() throws {
        let json = """
        {"id":"t","name":"t","rect":{"x":0,"y":0,"w":0,"h":0},
         "grid":{"rows":4,"cols":2,"labels":{"top":1,"left":1,"bottom":0,"right":0}},
         "columns":[],"body":[[],[]],"labels":{"top":[],"left":[],"bottom":[],"right":[]}}
        """
        let table = try JSONDecoder().decode(TableSnapshot.self, from: Data(json.utf8))
        // (left 1 + cols 2) * 80 wide ; (top 1 + rows 4) * 24 tall
        XCTAssertEqual(GridGeometry.size(table), CGSize(width: 3 * 80, height: 5 * 24))
    }
}
