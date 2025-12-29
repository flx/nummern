import Foundation
import Combine

final class CanvasViewModel: ObservableObject {
    @Published private(set) var project: ProjectModel
    @Published private(set) var pythonLog: String
    @Published private(set) var historyJSON: String

    private let transactionManager = TransactionManager()

    init(project: ProjectModel = ProjectModel()) {
        self.project = project
        self.pythonLog = ""
        self.historyJSON = ""
        rebuildLogs()
    }

    @discardableResult
    func addSheet(named name: String? = nil) -> SheetModel {
        let sheetName = name ?? nextSheetName()
        let command = AddSheetCommand(name: sheetName)
        apply(command)
        return project.sheets.first { $0.id == command.sheetId } ?? SheetModel(id: command.sheetId, name: sheetName)
    }

    @discardableResult
    func addTable(toSheetId sheetId: String,
                  name: String? = nil,
                  rect: Rect? = nil,
                  rows: Int = 10,
                  cols: Int = 6,
                  labels: LabelBands = LabelBands(topRows: 1, bottomRows: 0, leftCols: 1, rightCols: 0)) -> TableModel? {
        let tableName = name ?? nextTableName()
        let baseRect = rect ?? defaultTableRect()
        let tableId = ModelID.make()
        let command = AddTableCommand(
            sheetId: sheetId,
            tableId: tableId,
            name: tableName,
            rect: baseRect,
            rows: rows,
            cols: cols,
            labels: labels
        )
        apply(command)
        return table(withId: tableId)
    }

    func moveTable(tableId: String, to rect: Rect) {
        apply(SetTableRectCommand(tableId: tableId, rect: rect))
    }

    func resizeTable(tableId: String, width: Double, height: Double) {
        guard let table = table(withId: tableId) else {
            return
        }
        let rect = Rect(x: table.rect.x, y: table.rect.y, width: width, height: height)
        apply(SetTableRectCommand(tableId: tableId, rect: rect))
    }

    func updateTableRect(tableId: String, rect: Rect) {
        apply(SetTableRectCommand(tableId: tableId, rect: rect))
    }

    private func apply(_ command: any Command, kind: TransactionKind = .general) {
        transactionManager.begin(kind: kind)
        transactionManager.record(command)
        transactionManager.commit()
        var updated = project
        command.apply(to: &updated)
        project = updated
        rebuildLogs()
    }

    private func rebuildLogs() {
        pythonLog = transactionManager.pythonLog()
        historyJSON = encodeHistory(commands: transactionManager.allCommands())
    }

    private func encodeHistory(commands: [String]) -> String {
        let history = CommandHistory(commands: commands)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(history) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func nextSheetName() -> String {
        "Sheet \(project.sheets.count + 1)"
    }

    private func nextTableName() -> String {
        let count = project.sheets.reduce(0) { $0 + $1.tables.count }
        return "Table \(count + 1)"
    }

    private func defaultTableRect() -> Rect {
        let count = project.sheets.reduce(0) { $0 + $1.tables.count }
        let offset = Double(count) * 24.0
        return Rect(x: 80 + offset, y: 80 + offset, width: 320, height: 200)
    }

    private func table(withId id: String) -> TableModel? {
        for sheet in project.sheets {
            if let table = sheet.tables.first(where: { $0.id == id }) {
                return table
            }
        }
        return nil
    }
}
