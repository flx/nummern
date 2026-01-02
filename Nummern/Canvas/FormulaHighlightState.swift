import Foundation

struct FormulaReferenceKey: Hashable {
    let tableId: String
    let region: GridRegion
    let startRow: Int
    let startCol: Int
    let endRow: Int
    let endCol: Int
}

struct FormulaReferenceOccurrence: Hashable {
    let key: FormulaReferenceKey
    let location: Int
    let length: Int
}

struct FormulaHighlightState: Equatable {
    let tableId: String
    let text: String
    let references: [FormulaReferenceKey]
    let occurrences: [FormulaReferenceOccurrence]
}
