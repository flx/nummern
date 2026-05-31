import Foundation

/// Determines whether a cell is formula-defined by scanning the command log
/// (the app's source of truth) in reverse. The most recent writer wins:
/// if it's a `SetExpr`, the cell shows that expression; if it's a literal/clear,
/// the cell is a plain value. This is how the formula bar shows provenance
/// without storing formula text in the snapshot.
enum FormulaProvenance {
    static func expression(for tableId: String, ref: String, in commands: [Command]) -> String? {
        guard let cell = CellAddress.parseCell(ref) else { return nil }
        for command in commands.reversed() {
            if let e = command as? SetExprCommand, e.tableId == tableId, covers(e.target, cell) {
                return e.expr
            }
            if let l = command as? SetLiteralCommand, l.tableId == tableId, covers(l.range, cell) {
                return nil
            }
            if let c = command as? ClearRangeCommand, c.tableId == tableId, covers(c.range, cell) {
                return nil
            }
        }
        return nil
    }

    /// Does an A1 target (`"F0"`, `"F"`, `"F0:F9"`, `"F:H"`) include `cell`?
    static func covers(_ target: String, _ cell: (row: Int, col: Int)) -> Bool {
        if target.contains(":") {
            let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
            // Column range like "F:H"
            if parts.count == 2,
               let c0 = CellAddress.columnIndex(parts[0]),
               let c1 = CellAddress.columnIndex(parts[1]),
               parts.allSatisfy({ $0.allSatisfy(\.isLetter) }) {
                return cell.col >= min(c0, c1) && cell.col <= max(c0, c1)
            }
            if let r = CellAddress.parseRange(target) {
                return cell.row >= r.r0 && cell.row <= r.r1 && cell.col >= r.c0 && cell.col <= r.c1
            }
            return false
        }
        if let c = CellAddress.parseCell(target) {
            return c.row == cell.row && c.col == cell.col
        }
        // Whole column like "F"
        if target.allSatisfy({ $0.isLetter }), let col = CellAddress.columnIndex(target) {
            return cell.col == col
        }
        return false
    }
}
