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

    mutating func updateChart(id: String, _ mutate: (inout ChartModel) -> Void) {
        for sheetIndex in sheets.indices {
            if let chartIndex = sheets[sheetIndex].charts.firstIndex(where: { $0.id == id }) {
                mutate(&sheets[sheetIndex].charts[chartIndex])
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

    func nextChartId() -> String {
        let ids = sheets.flatMap { $0.charts.map(\.id) }
        return ModelID.nextChartId(existingIDs: ids)
    }

    func table(withId tableId: String) -> TableModel? {
        for sheet in sheets {
            if let table = sheet.tables.first(where: { $0.id == tableId }) {
                return table
            }
        }
        return nil
    }

    func chart(withId chartId: String) -> ChartModel? {
        for sheet in sheets {
            if let chart = sheet.charts.first(where: { $0.id == chartId }) {
                return chart
            }
        }
        return nil
    }
}
