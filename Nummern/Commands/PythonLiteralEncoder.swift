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
        case .date(let date):
            let formatted = dateFormatter.string(from: date)
            return "date_value(\(encodeString(formatted)))"
        case .time(let seconds):
            let date = referenceDate.addingTimeInterval(seconds)
            let formatted = timeFormatter.string(from: date)
            return "time_value(\(encodeString(formatted)))"
        case .empty:
            return "None"
        }
    }

    static func encodeString(_ string: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x5C:
                escaped.append("\\\\")
            case 0x27:
                escaped.append("\\'")
            case 0x0A:
                escaped.append("\\n")
            case 0x0D:
                escaped.append("\\r")
            case 0x09:
                escaped.append("\\t")
            case 0x00...0x1F, 0x7F:
                escaped.append(String(format: "\\x%02X", Int(scalar.value)))
            default:
                escaped.append(Character(scalar))
            }
        }
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

    private static let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
