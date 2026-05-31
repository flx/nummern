import Foundation

/// CSV encode/decode for import/export (README §5.7). Import parsing reuses
/// `ClipboardParser` (CSV mode with per-cell type inference); this adds RFC-4180
/// encoding and content-bounds trimming.
enum CSVCodec {
    static func encode(_ block: [[CellValue]]) -> String {
        block.map { row in row.map(field).joined(separator: ",") }
            .joined(separator: "\n")
    }

    private static func field(_ value: CellValue) -> String {
        switch value {
        case .empty: return ""
        case .number, .bool: return value.displayText()
        case .string(let s): return needsQuoting(s) ? quote(s) : s
        }
    }

    private static func needsQuoting(_ s: String) -> Bool {
        s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r")
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// The body block of a table trimmed to the last non-empty row/column.
    static func bodyBlock(_ table: TableSnapshot) -> [[CellValue]] {
        var lastRow = -1, lastCol = -1
        for r in 0..<table.grid.rows {
            for c in 0..<table.grid.cols where !table.cell(row: r, col: c).isEmpty {
                lastRow = max(lastRow, r)
                lastCol = max(lastCol, c)
            }
        }
        guard lastRow >= 0 else { return [] }
        return (0...lastRow).map { r in (0...lastCol).map { c in table.cell(row: r, col: c) } }
    }
}
