import Foundation

/// Derives chart ranges and summary specs from a selected rectangle of body
/// cells (README §5.10.5–6). Pure and testable; the document feeds it the
/// selected table's body region (range-scoped selection arrives with S7).
enum SelectionDerivation {
    struct Rect: Equatable { let r0: Int; let c0: Int; let r1: Int; let c1: Int }

    /// Body region of a table as a rect.
    static func bodyRect(_ table: TableSnapshot) -> Rect {
        Rect(r0: 0, c0: 0, r1: max(0, table.grid.rows - 1), c1: max(0, table.grid.cols - 1))
    }

    /// Line/bar/pie ranges: first column is the category axis; remaining columns
    /// are value series. A single-column rect has no separate category axis.
    static func chartRanges(_ rect: Rect) -> (value: String, label: String?) {
        func ref(_ r: Int, _ c: Int) -> String { "\(CellAddress.columnLabel(c))\(r)" }
        if rect.c1 > rect.c0 {
            let label = "\(ref(rect.r0, rect.c0)):\(ref(rect.r1, rect.c0))"
            let value = "\(ref(rect.r0, rect.c0 + 1)):\(ref(rect.r1, rect.c1))"
            return (value, label)
        }
        return ("\(ref(rect.r0, rect.c0)):\(ref(rect.r1, rect.c1))", nil)
    }

    /// Summary: group by the first column of the rect; sum each numeric column
    /// after it. `scoped` records the rect as a `source_range` (range selection).
    static func summarySpec(_ rect: Rect, table: TableSnapshot, scoped: Bool)
        -> (groupBy: [String], values: [(col: String, agg: String)], sourceRange: String?) {
        let groupBy = [CellAddress.columnLabel(rect.c0)]
        var values: [(col: String, agg: String)] = []
        for col in (rect.c0 + 1)...max(rect.c0 + 1, rect.c1) where col <= rect.c1 {
            if isNumericColumn(table, col: col) {
                values.append((CellAddress.columnLabel(col), "sum"))
            }
        }
        if values.isEmpty, rect.c1 > rect.c0 {
            values = [(CellAddress.columnLabel(rect.c0 + 1), "sum")]
        }
        let sourceRange: String? = scoped
            ? "body[\(CellAddress.columnLabel(rect.c0))\(rect.r0):\(CellAddress.columnLabel(rect.c1))\(rect.r1)]"
            : nil
        return (groupBy, values, sourceRange)
    }

    private static func isNumericColumn(_ table: TableSnapshot, col: Int) -> Bool {
        table.columns.first { $0.index == col }?.dtype == "number"
    }
}
