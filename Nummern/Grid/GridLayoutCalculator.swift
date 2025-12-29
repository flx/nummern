import Foundation

struct GridIndexRange: Equatable {
    let rowRange: Range<Int>
    let colRange: Range<Int>
}

struct GridLayoutCalculator {
    static func visibleRange(visibleRect: CGRect,
                             cellSize: CGSize,
                             rows: Int,
                             cols: Int) -> GridIndexRange {
        guard rows > 0, cols > 0, cellSize.width > 0, cellSize.height > 0 else {
            return GridIndexRange(rowRange: 0..<0, colRange: 0..<0)
        }

        let minRow = max(0, Int(floor(visibleRect.minY / cellSize.height)))
        let maxRow = min(rows, Int(ceil(visibleRect.maxY / cellSize.height)))
        let minCol = max(0, Int(floor(visibleRect.minX / cellSize.width)))
        let maxCol = min(cols, Int(ceil(visibleRect.maxX / cellSize.width)))

        return GridIndexRange(rowRange: minRow..<maxRow, colRange: minCol..<maxCol)
    }
}
