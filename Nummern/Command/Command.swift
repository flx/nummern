import Foundation

/// A recorded user action. Each command renders to exactly one line of plain
/// Python (`toPython()`), so the generated script reads like — and *is* — code a
/// user could have written. There is no `table_context` wrapping or magic.
protocol Command {
    /// One line of Python appended to the generated region.
    func toPython() -> String
}

/// Python variable name used for an object id in the generated script.
/// Ids are already valid identifiers (`sheet_1`, `table_1`), so they double as
/// variable names — which is what enables `table_1["F"] = table_1["B"] + ...`.
enum PyVar {
    static func valid(_ id: String) -> Bool {
        guard let first = id.first, first.isLetter || first == "_" else { return false }
        return id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
