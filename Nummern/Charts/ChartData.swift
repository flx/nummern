import Foundation

/// Turns a chart spec + its source table snapshot into renderable series.
/// Multi-series: each column of the value range is a series; categories come
/// from the label range (or row indices); series names from the top label row
/// (or column letters). Reads computed values, so charts reflect the latest run.
enum ChartData {
    struct Point: Identifiable {
        let id = UUID()
        let category: String
        let value: Double
    }
    struct Series: Identifiable {
        let id = UUID()
        let name: String
        let points: [Point]
    }

    static func series(chart: ChartSnapshot, table: TableSnapshot) -> [Series] {
        guard let value = CellAddress.parseRange(chart.value_range) else { return [] }
        let categories = categoryLabels(chart: chart, table: table,
                                         rowCount: value.r1 - value.r0 + 1, rowStart: value.r0)
        var result: [Series] = []
        for col in value.c0...value.c1 {
            var points: [Point] = []
            for (i, row) in (value.r0...value.r1).enumerated() {
                if let number = numericValue(table.cell(row: row, col: col)) {
                    points.append(Point(category: categories[i], value: number))
                }
            }
            result.append(Series(name: seriesName(table: table, col: col), points: points))
        }
        return result
    }

    /// Pie uses the first value column only.
    static func pieSlices(chart: ChartSnapshot, table: TableSnapshot) -> [Point] {
        series(chart: chart, table: table).first?.points ?? []
    }

    private static func categoryLabels(chart: ChartSnapshot, table: TableSnapshot,
                                       rowCount: Int, rowStart: Int) -> [String] {
        if let labelRange = chart.label_range, let r = CellAddress.parseRange(labelRange) {
            var labels: [String] = []
            for i in 0..<rowCount {
                let row = r.r0 + i
                let cell = table.cell(row: row, col: r.c0)
                labels.append(cell.isEmpty ? "\(row)" : cell.displayText())
            }
            return labels
        }
        return (0..<rowCount).map { "\(rowStart + $0)" }
    }

    private static func seriesName(table: TableSnapshot, col: Int) -> String {
        if table.grid.labels.top > 0 {
            let header = table.bandCell("top", row: 0, col: col)
            if !header.isEmpty { return header.displayText() }
        }
        return CellAddress.columnLabel(col)
    }

    private static func numericValue(_ cell: CellValue) -> Double? {
        switch cell {
        case .number(let d): return d
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }
}
