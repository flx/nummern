import XCTest
@testable import Nummern

final class GridIndexingTests: XCTestCase {
    func testVisibleRangeMapping() {
        let visibleRect = CGRect(x: 0, y: 0, width: 120, height: 60)
        let cellSize = CGSize(width: 40, height: 20)
        let range = GridLayoutCalculator.visibleRange(
            visibleRect: visibleRect,
            cellSize: cellSize,
            rows: 10,
            cols: 10
        )

        XCTAssertEqual(range.rowRange, 0..<3)
        XCTAssertEqual(range.colRange, 0..<3)
    }

    func testVisibleRangeOffset() {
        let visibleRect = CGRect(x: 30, y: 25, width: 80, height: 45)
        let cellSize = CGSize(width: 20, height: 15)
        let range = GridLayoutCalculator.visibleRange(
            visibleRect: visibleRect,
            cellSize: cellSize,
            rows: 10,
            cols: 10
        )

        XCTAssertEqual(range.rowRange, 1..<5)
        XCTAssertEqual(range.colRange, 1..<6)
    }
}
