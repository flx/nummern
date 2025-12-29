import Foundation
import Combine

final class ProjectStore: ObservableObject {
    @Published private(set) var project: ProjectModel

    init(project: ProjectModel = ProjectModel()) {
        self.project = project
    }

    @discardableResult
    func addSheet(name: String) -> SheetModel {
        let sheetId = project.nextSheetId()
        let sheet = SheetModel(id: sheetId, name: name)
        project.sheets.append(sheet)
        return sheet
    }

    func renameSheet(id: String, to name: String) {
        guard let index = project.sheets.firstIndex(where: { $0.id == id }) else {
            return
        }
        project.sheets[index].name = name
    }

    @discardableResult
    func addTable(sheetId: String,
                  name: String,
                  rect: Rect,
                  rows: Int = 10,
                  cols: Int = 6,
                  labelBands: LabelBands = .zero) -> TableModel? {
        guard let index = project.sheets.firstIndex(where: { $0.id == sheetId }) else {
            return nil
        }
        let tableId = project.nextTableId()
        let table = TableModel(id: tableId, name: name, rect: rect, rows: rows, cols: cols, labelBands: labelBands)
        project.sheets[index].tables.append(table)
        return table
    }

    func updateTableRect(tableId: String, rect: Rect) {
        for sheetIndex in project.sheets.indices {
            if let tableIndex = project.sheets[sheetIndex].tables.firstIndex(where: { $0.id == tableId }) {
                project.sheets[sheetIndex].tables[tableIndex].rect = rect
                return
            }
        }
    }
}
