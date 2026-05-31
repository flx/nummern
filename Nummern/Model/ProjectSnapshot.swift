import Foundation

/// Decoded mirror of the engine's `to_json` contract (see python/canvassheets/io.py).
/// This is the *display* model: the app renders snapshots and records edits as
/// Python statements; it never mutates a snapshot directly as a source of truth.

struct RectDTO: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

struct LabelBandsDTO: Codable, Equatable {
    var top: Int
    var left: Int
    var bottom: Int
    var right: Int
}

struct GridDTO: Codable, Equatable {
    var rows: Int
    var cols: Int
    var labels: LabelBandsDTO
}

struct ColumnInfo: Codable, Equatable {
    var index: Int
    var name: String?
    var dtype: String
    var format: String?
}

struct SummaryDTO: Codable, Equatable {
    struct Value: Codable, Equatable {
        var col: String
        var agg: String
    }
    var source_table_id: String
    var group_by: [String]
    var values: [Value]
    var source_range: String?
}

struct TableSnapshot: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var rect: RectDTO
    var grid: GridDTO
    var columns: [ColumnInfo]
    /// Column-major body: `body[col][row]`.
    var body: [[CellValue]]
    /// Label band grids keyed by region ("top"/"left"/"bottom"/"right").
    var labels: [String: [[CellValue]]]
    var summary: SummaryDTO?

    func cell(row: Int, col: Int) -> CellValue {
        guard col >= 0, col < body.count, row >= 0, row < body[col].count else { return .empty }
        return body[col][row]
    }

    func bandCell(_ region: String, row: Int, col: Int) -> CellValue {
        guard let grid = labels[region], row >= 0, row < grid.count,
              col >= 0, col < grid[row].count else { return .empty }
        return grid[row][col]
    }
}

struct ChartSnapshot: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var chart_type: String
    var table_id: String
    var value_range: String
    var label_range: String?
    var title: String
    var x_axis_title: String
    var y_axis_title: String
    var show_legend: Bool
    var rect: RectDTO
}

struct SheetSnapshot: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var tables: [TableSnapshot]
    var charts: [ChartSnapshot]
}

struct ProjectSnapshot: Codable, Equatable {
    var version: Int
    var sheets: [SheetSnapshot]

    static let empty = ProjectSnapshot(version: 1, sheets: [])

    func sheet(id: String) -> SheetSnapshot? { sheets.first { $0.id == id } }
    func table(id: String) -> TableSnapshot? {
        for sheet in sheets { if let t = sheet.tables.first(where: { $0.id == id }) { return t } }
        return nil
    }
}
