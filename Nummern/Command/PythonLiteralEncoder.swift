import Foundation

/// Encodes Swift values into Python literal source. Used to render commands as
/// one line of plain Python each.
enum PythonLiteralEncoder {
    static func string(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\x%02x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }

    static func number(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    static func cell(_ value: CellValue) -> String {
        switch value {
        case .number(let d): return number(d)
        case .string(let s): return string(s)
        case .bool(let b): return b ? "True" : "False"
        case .empty: return "None"
        }
    }

    static func row(_ values: [CellValue]) -> String {
        "[" + values.map(cell).joined(separator: ", ") + "]"
    }

    static func grid(_ values: [[CellValue]]) -> String {
        "[" + values.map(row).joined(separator: ", ") + "]"
    }

    static func stringList(_ values: [String]) -> String {
        "[" + values.map(string).joined(separator: ", ") + "]"
    }

    /// `dict(top=1, left=1, bottom=0, right=0)`
    static func labelsKwarg(_ bands: LabelBandsDTO) -> String {
        "dict(top=\(bands.top), left=\(bands.left), bottom=\(bands.bottom), right=\(bands.right))"
    }
}
