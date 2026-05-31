import Foundation

/// Interpretation of text typed into a cell or the formula bar.
///
/// A leading `=` marks a formula — recorded verbatim as a Python expression via
/// `SetExpr` (formulas *are* Python; see the v2 plan). Otherwise the text is a
/// literal parsed into a `CellValue`.
enum CellInput: Equatable {
    case literal(CellValue)
    case formula(String)

    static func parse(_ raw: String) -> CellInput {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("=") {
            return .formula(String(text.dropFirst()).trimmingCharacters(in: .whitespaces))
        }
        return .literal(literalValue(text))
    }

    static func literalValue(_ text: String) -> CellValue {
        if text.isEmpty { return .empty }
        let lower = text.lowercased()
        if lower == "true" { return .bool(true) }
        if lower == "false" { return .bool(false) }
        if let i = Int(text) { return .number(Double(i)) }
        if let d = Double(text) { return .number(d) }
        return .string(text)
    }
}
