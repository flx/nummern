import Foundation

struct CellSelection: Equatable, Hashable {
    let tableId: String
    let region: GridRegion
    let row: Int
    let col: Int
}

struct TableRangeSelection: Equatable, Hashable {
    let tableId: String
    let region: GridRegion
    let startRow: Int
    let startCol: Int
    let endRow: Int
    let endCol: Int

    init(tableId: String, region: GridRegion, startRow: Int, startCol: Int, endRow: Int, endCol: Int) {
        self.tableId = tableId
        self.region = region
        self.startRow = startRow
        self.startCol = startCol
        self.endRow = endRow
        self.endCol = endCol
    }

    init(cell: CellSelection) {
        self.init(tableId: cell.tableId,
                  region: cell.region,
                  startRow: cell.row,
                  startCol: cell.col,
                  endRow: cell.row,
                  endCol: cell.col)
    }

    var normalized: TableRangeSelection {
        let rowStart = min(startRow, endRow)
        let rowEnd = max(startRow, endRow)
        let colStart = min(startCol, endCol)
        let colEnd = max(startCol, endCol)
        return TableRangeSelection(tableId: tableId,
                                   region: region,
                                   startRow: rowStart,
                                   startCol: colStart,
                                   endRow: rowEnd,
                                   endCol: colEnd)
    }

    var isSingleCell: Bool {
        let norm = normalized
        return norm.startRow == norm.endRow && norm.startCol == norm.endCol
    }

    var startCell: CellSelection {
        let norm = normalized
        return CellSelection(tableId: tableId, region: region, row: norm.startRow, col: norm.startCol)
    }

    var endCell: CellSelection {
        let norm = normalized
        return CellSelection(tableId: tableId, region: region, row: norm.endRow, col: norm.endCol)
    }

    func contains(_ cell: CellSelection) -> Bool {
        guard cell.tableId == tableId, cell.region == region else {
            return false
        }
        let norm = normalized
        return cell.row >= norm.startRow && cell.row <= norm.endRow
            && cell.col >= norm.startCol && cell.col <= norm.endCol
    }

    func rangeString() -> String {
        let norm = normalized
        return RangeParser.rangeString(region: region,
                                       startRow: norm.startRow,
                                       startCol: norm.startCol,
                                       endRow: norm.endRow,
                                       endCol: norm.endCol)
    }
}
