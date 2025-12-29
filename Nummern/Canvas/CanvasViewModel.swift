import AppKit
import Combine
import Foundation

final class CanvasViewModel: ObservableObject {
    @Published private(set) var project: ProjectModel
    @Published private(set) var pythonLog: String
    @Published private(set) var historyJSON: String
    @Published var selectedTableId: String?
    @Published var selectedCell: CellSelection?

    private let transactionManager = TransactionManager()

    init(project: ProjectModel = ProjectModel()) {
        self.project = project
        self.pythonLog = ""
        self.historyJSON = ""
        self.selectedTableId = nil
        self.selectedCell = nil
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

    func setLabelBands(tableId: String, labelBands: LabelBands) {
        apply(SetLabelBandsCommand(tableId: tableId, labelBands: labelBands))
    }

    func selectTable(_ tableId: String) {
        selectedTableId = tableId
    }

    func selectCell(_ selection: CellSelection) {
        selectedTableId = selection.tableId
        selectedCell = selection
    }

    func clearCellSelection() {
        selectedCell = nil
    }

    func setCellValue(tableId: String,
                      region: GridRegion,
                      row: Int,
                      col: Int,
                      rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: CellValue
        if region == .body {
            value = CellValue.fromUserInput(rawValue)
        } else {
            value = trimmed.isEmpty ? .empty : .string(trimmed)
        }
        let key = RangeParser.address(region: region, row: row, col: col)
        apply(SetCellsCommand(tableId: tableId, cellMap: [key: value]), kind: .cellEdit)
    }

    func setRange(tableId: String,
                  region: GridRegion,
                  startRow: Int,
                  startCol: Int,
                  values: [[CellValue]]) {
        guard let firstRow = values.first, !firstRow.isEmpty else {
            return
        }
        let endRow = startRow + values.count - 1
        let endCol = startCol + firstRow.count - 1
        let range = RangeParser.rangeString(region: region,
                                            startRow: startRow,
                                            startCol: startCol,
                                            endRow: endRow,
                                            endCol: endCol)
        apply(SetRangeCommand(tableId: tableId, range: range, values: values), kind: .general)
    }

    func copySelectionToClipboard() {
        guard let selection = selectedCell,
              let table = table(withId: selection.tableId) else {
            return
        }
        let key = RangeParser.address(region: selection.region, row: selection.row, col: selection.col)
        let text = table.cellValues[key]?.displayString ?? ""
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func pasteFromClipboard() {
        guard let selection = selectedCell,
              let text = NSPasteboard.general.string(forType: .string),
              !text.isEmpty else {
            return
        }
        let values = ClipboardParser.values(from: text, region: selection.region)
        guard !values.isEmpty, !(values.first?.isEmpty ?? true) else {
            return
        }
        setRange(tableId: selection.tableId,
                 region: selection.region,
                 startRow: selection.row,
                 startCol: selection.col,
                 values: values)
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

    func selectedTable() -> TableModel? {
        guard let selectedTableId else {
            return nil
        }
        return table(withId: selectedTableId)
    }
}
