import Foundation

struct ClipboardParser {
    static func parse(_ text: String) -> [[String]] {
        if text.contains("\t") {
            return parseTabDelimited(text)
        }
        return CSVCodec.parse(text)
    }

    static func values(from text: String, region: GridRegion) -> [[CellValue]] {
        let rows = parse(text)
        return rows.map { row in
            row.map { item in
                if region == .body {
                    return CellValue.fromUserInput(item)
                }
                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? .empty : .string(trimmed)
            }
        }
    }

    private static func parseTabDelimited(_ text: String) -> [[String]] {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        while lines.count > 1, lines.last == "" {
            lines.removeLast()
        }
        guard !lines.isEmpty else {
            return []
        }
        return lines.map { line in
            line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        }
    }
}

struct CSVTableImport: Equatable {
    let values: [[CellValue]]
    let columnTypes: [ColumnDataType]
}

enum CSVTableImporter {
    static func parse(_ text: String) -> CSVTableImport? {
        let rawRows = CSVCodec.parse(text)
        guard !rawRows.isEmpty else {
            return nil
        }
        let maxCols = rawRows.map(\.count).max() ?? 0
        guard maxCols > 0 else {
            return nil
        }
        let paddedRows = rawRows.map { row in
            if row.count == maxCols {
                return row
            }
            return row + Array(repeating: "", count: maxCols - row.count)
        }
        let columnTypes = inferColumnTypes(from: paddedRows)
        let values = paddedRows.map { row in
            row.enumerated().map { index, item in
                let columnType = columnTypes[index]
                return CellValue.fromUserInput(item, columnType: columnType) ?? .empty
            }
        }
        return CSVTableImport(values: values, columnTypes: columnTypes)
    }

    private static func inferColumnTypes(from rows: [[String]]) -> [ColumnDataType] {
        guard let firstRow = rows.first else {
            return []
        }
        let columnCount = firstRow.count
        return (0..<columnCount).map { col in
            let values = rows.map { $0[col] }
            return inferColumnType(values)
        }
    }

    private static func inferColumnType(_ values: [String]) -> ColumnDataType {
        let nonEmpty = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else {
            return .number
        }
        if allMatch(nonEmpty, as: .date) {
            return .date
        }
        if allMatch(nonEmpty, as: .time) {
            return .time
        }
        if nonEmpty.contains(where: hasCurrencySymbol),
           allMatch(nonEmpty, as: .currency) {
            return .currency
        }
        if nonEmpty.contains(where: { $0.contains("%") }),
           allMatch(nonEmpty, as: .percentage) {
            return .percentage
        }
        if allNumbersOrBools(nonEmpty) {
            return .number
        }
        return .string
    }

    private static func allMatch(_ values: [String], as columnType: ColumnDataType) -> Bool {
        values.allSatisfy { CellValue.fromUserInput($0, columnType: columnType) != nil }
    }

    private static func allNumbersOrBools(_ values: [String]) -> Bool {
        values.allSatisfy { value in
            switch CellValue.fromUserInput(value) {
            case .number, .bool:
                return true
            default:
                return false
            }
        }
    }

    private static func hasCurrencySymbol(_ value: String) -> Bool {
        let localeSymbol = Locale.current.currencySymbol ?? ""
        let commonSymbols: [Character] = ["$", "€", "£", "¥", "₩", "₹", "₽", "₺", "₪", "₫", "฿"]
        let symbolSet = Set(localeSymbol + String(commonSymbols))
        return value.contains { symbolSet.contains($0) }
    }
}

enum CSVTableExporter {
    static func export(table: TableModel) -> String {
        let bounds = table.bodyContentBounds()
        let rowCount = bounds.map { $0.maxRow + 1 } ?? 0
        let colCount = bounds.map { $0.maxCol + 1 } ?? 0
        guard rowCount > 0, colCount > 0 else {
            return ""
        }
        var rows: [[String]] = []
        for row in 0..<rowCount {
            var rowValues: [String] = []
            for col in 0..<colCount {
                let key = RangeParser.address(region: .body, row: row, col: col)
                let value = table.cellValues[key] ?? .empty
                let columnType = table.bodyColumnTypes.indices.contains(col)
                    ? table.bodyColumnTypes[col]
                    : .number
                rowValues.append(CellValue.displayString(value, columnType: columnType))
            }
            rows.append(rowValues)
        }
        return CSVCodec.encode(rows)
    }
}

enum CSVCodec {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        let chars = Array(text)
        var index = 0

        func finishField() {
            currentRow.append(currentField)
            currentField = ""
        }

        func finishRow() {
            finishField()
            rows.append(currentRow)
            currentRow = []
        }

        while index < chars.count {
            let char = chars[index]
            if inQuotes {
                if char == "\"" {
                    let nextIndex = index + 1
                    if nextIndex < chars.count, chars[nextIndex] == "\"" {
                        currentField.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                    index += 1
                    continue
                }
                currentField.append(char)
                index += 1
                continue
            }

            switch char {
            case "\"":
                inQuotes = true
            case ",":
                finishField()
            case "\n":
                finishRow()
            case "\r":
                finishRow()
                let nextIndex = index + 1
                if nextIndex < chars.count, chars[nextIndex] == "\n" {
                    index += 1
                }
            default:
                currentField.append(char)
            }
            index += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            finishRow()
        }

        return rows
    }

    static func encode(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map(escapeField).joined(separator: ",")
        }.joined(separator: "\n")
    }

    private static func escapeField(_ field: String) -> String {
        let needsQuotes = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        if !needsQuotes {
            return field
        }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
