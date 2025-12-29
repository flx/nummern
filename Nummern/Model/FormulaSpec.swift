import Foundation

enum FormulaMode: String, Codable, Equatable, Hashable {
    case spreadsheet
    case python
}

struct FormulaSpec: Codable, Equatable, Hashable {
    var formula: String
    var mode: FormulaMode

    init(formula: String, mode: FormulaMode = .spreadsheet) {
        self.formula = formula
        self.mode = mode
    }
}
