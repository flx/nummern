import Foundation

struct ProjectModel: Codable, Equatable {
    var sheets: [SheetModel]

    init(sheets: [SheetModel] = []) {
        self.sheets = sheets
    }

    mutating func updateSheet(id: String, _ mutate: (inout SheetModel) -> Void) {
        guard let index = sheets.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&sheets[index])
    }

    mutating func updateTable(id: String, _ mutate: (inout TableModel) -> Void) {
        for sheetIndex in sheets.indices {
            if let tableIndex = sheets[sheetIndex].tables.firstIndex(where: { $0.id == id }) {
                mutate(&sheets[sheetIndex].tables[tableIndex])
                return
            }
        }
    }
}

extension ProjectModel {
    func nextSheetId() -> String {
        ModelID.nextSheetId(existingIDs: sheets.map(\.id))
    }

    func nextTableId() -> String {
        let ids = sheets.flatMap { $0.tables.map(\.id) }
        return ModelID.nextTableId(existingIDs: ids)
    }

    func table(withId tableId: String) -> TableModel? {
        for sheet in sheets {
            if let table = sheet.tables.first(where: { $0.id == tableId }) {
                return table
            }
        }
        return nil
    }
}
