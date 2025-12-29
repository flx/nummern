import Foundation

struct ClipboardParser {
    static func parse(_ text: String) -> [[String]] {
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
}
