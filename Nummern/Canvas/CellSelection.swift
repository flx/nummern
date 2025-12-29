import Foundation

struct CellSelection: Equatable, Hashable {
    let tableId: String
    let region: GridRegion
    let row: Int
    let col: Int
}
