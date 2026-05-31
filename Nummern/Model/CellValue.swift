import Foundation

/// A single decoded cell value from the engine. The engine sends raw JSON
/// scalars (numbers, strings, bools, null); the owning column's `dtype` tells
/// the UI how to format it (e.g. a `datetime` column carries ISO strings).
enum CellValue: Equatable, Codable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case empty

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .empty
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? container.decode(Double.self) {
            self = .number(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            self = .empty
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .bool(let b): try container.encode(b)
        case .empty: try container.encodeNil()
        }
    }

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    /// A plain display string (locale-aware formatting per column type is layered on later).
    func displayText() -> String {
        switch self {
        case .number(let d):
            if d == d.rounded() && abs(d) < 1e15 {
                return String(Int64(d))
            }
            return String(d)
        case .string(let s): return s
        case .bool(let b): return b ? "TRUE" : "FALSE"
        case .empty: return ""
        }
    }
}
