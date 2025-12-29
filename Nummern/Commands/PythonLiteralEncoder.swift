import Foundation

struct PythonLiteralEncoder {
    static func encode(_ value: CellValue) -> String {
        switch value {
        case .string(let string):
            return encodeString(string)
        case .number(let number):
            return encodeNumber(number)
        case .bool(let bool):
            return bool ? "True" : "False"
        case .empty:
            return "None"
        }
    }

    static func encodeString(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }

    static func encodeNumber(_ number: Double) -> String {
        if number.rounded() == number {
            return String(Int(number))
        }
        return String(number)
    }

    static func encodeList(_ values: [CellValue]) -> String {
        let items = values.map { encode($0) }.joined(separator: ", ")
        return "[\(items)]"
    }

    static func encodeStringList(_ values: [String]) -> String {
        let items = values.map { encodeString($0) }.joined(separator: ", ")
        return "[\(items)]"
    }

    static func encode2D(_ values: [[CellValue]]) -> String {
        let rows = values.map { encodeList($0) }.joined(separator: ", ")
        return "[\(rows)]"
    }

    static func encodeDict(_ values: [String: CellValue]) -> String {
        let items = values.keys.sorted().map { key in
            let value = values[key] ?? .empty
            return "\(encodeString(key)): \(encode(value))"
        }
        return "{\(items.joined(separator: ", "))}"
    }

    static func encodeRect(_ rect: Rect) -> String {
        "Rect(\(encodeNumber(rect.x)), \(encodeNumber(rect.y)), \(encodeNumber(rect.width)), \(encodeNumber(rect.height)))"
    }

    static func encodeLabels(_ labels: LabelBands) -> String {
        "dict(top=\(labels.topRows), left=\(labels.leftCols), bottom=\(labels.bottomRows), right=\(labels.rightCols))"
    }
}
