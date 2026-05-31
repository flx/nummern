import Foundation

/// Parses pasted text into a 2D block of cell values. Uses TSV when any tab is
/// present (the system clipboard's table format), otherwise CSV (README §5.7).
enum ClipboardParser {
    static func parse(_ text: String) -> [[CellValue]] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let last = lines.last, last.isEmpty { lines.removeLast() }
        guard !lines.isEmpty else { return [] }

        let useTab = normalized.contains("\t")
        return lines.map { line in
            let fields = useTab ? splitTab(line) : splitCSV(line)
            return fields.map { CellInput.literalValue($0) }
        }
    }

    private static func splitTab(_ line: String) -> [String] {
        line.components(separatedBy: "\t")
    }

    /// Minimal RFC-4180-ish CSV: handles quoted fields and escaped quotes.
    private static func splitCSV(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var pending: Character? = iterator.next()
        while let ch = pending {
            pending = iterator.next()
            if inQuotes {
                if ch == "\"" {
                    if pending == "\"" { current.append("\""); pending = iterator.next() }
                    else { inQuotes = false }
                } else {
                    current.append(ch)
                }
            } else {
                switch ch {
                case "\"": inQuotes = true
                case ",": fields.append(current); current = ""
                default: current.append(ch)
                }
            }
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Render a block as TSV for copying out.
    static func tsv(_ block: [[CellValue]]) -> String {
        block.map { row in row.map { $0.displayText() }.joined(separator: "\t") }
            .joined(separator: "\n")
    }
}
