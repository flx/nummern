import Foundation

/// Maps a table's full grid (label bands + body) to addressable cells.
/// Cell footprint matches the engine (80×24 points).
enum GridGeometry {
    static let cellWidth: CGFloat = 80
    static let cellHeight: CGFloat = 24

    enum Region { case body, top, left, bottom, right, corner }

    struct CellInfo {
        let region: Region
        let value: CellValue
        /// Coordinates within the region's own grid (for body: body row/col).
        let row: Int
        let col: Int
    }

    static func totalCols(_ t: TableSnapshot) -> Int {
        t.grid.labels.left + t.grid.cols + t.grid.labels.right
    }
    static func totalRows(_ t: TableSnapshot) -> Int {
        t.grid.labels.top + t.grid.rows + t.grid.labels.bottom
    }

    static func size(_ t: TableSnapshot) -> CGSize {
        CGSize(width: CGFloat(totalCols(t)) * cellWidth, height: CGFloat(totalRows(t)) * cellHeight)
    }

    /// Rows whose vertical span intersects `rect` — drives virtualized drawing.
    static func visibleRows(in rect: CGRect, totalRows: Int) -> Range<Int> {
        visibleSpan(start: rect.minY, end: rect.maxY, step: cellHeight, count: totalRows)
    }

    static func visibleCols(in rect: CGRect, totalCols: Int) -> Range<Int> {
        visibleSpan(start: rect.minX, end: rect.maxX, step: cellWidth, count: totalCols)
    }

    private static func visibleSpan(start: CGFloat, end: CGFloat, step: CGFloat, count: Int) -> Range<Int> {
        guard count > 0, step > 0, end > start else { return 0..<0 }
        let first = max(0, Int((start / step).rounded(.down)))
        let last = min(count, Int((end / step).rounded(.up)))
        return first < last ? first..<last : 0..<0
    }

    /// Resolve a full-grid coordinate `(gr, gc)` to its region and value.
    static func cell(_ t: TableSnapshot, gr: Int, gc: Int) -> CellInfo {
        let lab = t.grid.labels
        let bodyRowStart = lab.top
        let bodyRowEnd = lab.top + t.grid.rows          // exclusive
        let bodyColStart = lab.left
        let bodyColEnd = lab.left + t.grid.cols          // exclusive

        let inBodyRows = gr >= bodyRowStart && gr < bodyRowEnd
        let inBodyCols = gc >= bodyColStart && gc < bodyColEnd

        if inBodyRows && inBodyCols {
            let r = gr - bodyRowStart, c = gc - bodyColStart
            return CellInfo(region: .body, value: t.cell(row: r, col: c), row: r, col: c)
        }
        if gr < bodyRowStart && inBodyCols {
            let r = gr, c = gc - bodyColStart
            return CellInfo(region: .top, value: t.bandCell("top", row: r, col: c), row: r, col: c)
        }
        if gr >= bodyRowEnd && inBodyCols {
            let r = gr - bodyRowEnd, c = gc - bodyColStart
            return CellInfo(region: .bottom, value: t.bandCell("bottom", row: r, col: c), row: r, col: c)
        }
        if gc < bodyColStart && inBodyRows {
            let r = gr - bodyRowStart, c = gc
            return CellInfo(region: .left, value: t.bandCell("left", row: r, col: c), row: r, col: c)
        }
        if gc >= bodyColEnd && inBodyRows {
            let r = gr - bodyRowStart, c = gc - bodyColEnd
            return CellInfo(region: .right, value: t.bandCell("right", row: r, col: c), row: r, col: c)
        }
        return CellInfo(region: .corner, value: .empty, row: 0, col: 0)
    }
}
