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
    private var seedCommands: [String] = []
    private let cellSize = CanvasGridSizing.cellSize

    init(project: ProjectModel = ProjectModel(), historyJSON: String? = nil) {
        self.project = project
        self.pythonLog = ""
        self.historyJSON = ""
        self.selectedTableId = nil
        self.selectedCell = nil
        self.seedCommands = decodeHistoryCommands(from: historyJSON)
        rebuildLogs()
    }

    func load(project: ProjectModel, historyJSON: String?) {
        transactionManager.reset()
        seedCommands = decodeHistoryCommands(from: historyJSON)
        self.project = project
        selectedTableId = nil
        selectedCell = nil
        rebuildLogs()
    }

    @discardableResult
    func addSheet(named name: String? = nil) -> SheetModel {
        let sheetName = name ?? nextSheetName()
        let sheetId = project.nextSheetId()
        let command = AddSheetCommand(name: sheetName, sheetId: sheetId)
        apply(command)
        return project.sheets.first { $0.id == sheetId } ?? SheetModel(id: sheetId, name: sheetName)
    }

    @discardableResult
    func addTable(toSheetId sheetId: String,
                  name: String? = nil,
                  rect: Rect? = nil,
                  rows: Int = 10,
                  cols: Int = 6,
                  labels: LabelBands = LabelBands(topRows: 1, bottomRows: 0, leftCols: 1, rightCols: 0)) -> TableModel? {
        let tableId = project.nextTableId()
        let tableName = name ?? tableId
        let baseRect = rect ?? defaultTableRect(rows: rows, cols: cols, labelBands: labels)
        let sizedRect = rectWithGridSize(baseRect, rows: rows, cols: cols, labelBands: labels)
        let command = AddTableCommand(
            sheetId: sheetId,
            tableId: tableId,
            name: tableName,
            rect: sizedRect,
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

    func updateTableRect(tableId: String, rect: Rect) {
        apply(SetTableRectCommand(tableId: tableId, rect: rect))
    }

    func setLabelBands(tableId: String, labelBands: LabelBands) {
        apply(SetLabelBandsCommand(tableId: tableId, labelBands: labelBands))
        syncTableRect(tableId: tableId)
        clearCellSelectionIfInvalid(tableId: tableId)
    }

    func setBodySize(tableId: String, rows: Int, cols: Int) {
        let safeRows = max(CanvasGridSizing.minBodyRows, rows)
        let safeCols = max(CanvasGridSizing.minBodyCols, cols)
        apply(ResizeTableCommand(tableId: tableId, rows: safeRows, cols: safeCols))
        syncTableRect(tableId: tableId)
    }

    func setBodyRows(tableId: String, rows: Int) {
        let safeRows = max(CanvasGridSizing.minBodyRows, rows)
        apply(ResizeTableCommand(tableId: tableId, rows: safeRows))
        syncTableRect(tableId: tableId)
    }

    func setBodyCols(tableId: String, cols: Int) {
        let safeCols = max(CanvasGridSizing.minBodyCols, cols)
        apply(ResizeTableCommand(tableId: tableId, cols: safeCols))
        syncTableRect(tableId: tableId)
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

    func clearSelection() {
        selectedCell = nil
        selectedTableId = nil
    }

    func setCellValue(tableId: String,
                      region: GridRegion,
                      row: Int,
                      col: Int,
                      rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = RangeParser.address(region: region, row: row, col: col)
        guard let table = table(withId: tableId) else {
            return
        }

        if region == .body, trimmed.hasPrefix("=") {
            let formulaText = trimmed == "=" ? "" : trimmed
            let existingFormula = table.formulas[key]?.formula ?? ""
            if existingFormula == formulaText {
                return
            }
            apply(SetFormulaCommand(tableId: tableId,
                                    targetRange: key,
                                    formula: formulaText),
                  kind: .cellEdit)
            return
        }

        if region == .body,
           let existingFormula = table.formulas[key],
           !existingFormula.formula.isEmpty {
            apply(SetFormulaCommand(tableId: tableId,
                                    targetRange: key,
                                    formula: ""),
                  kind: .cellEdit)
        }

        let value: CellValue
        if region == .body {
            value = CellValue.fromUserInput(rawValue)
        } else {
            value = trimmed.isEmpty ? .empty : .string(trimmed)
        }
        let existing = table.cellValues[key] ?? .empty
        if existing == value {
            return
        }
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
        let commands = seedCommands + transactionManager.allCommands()
        let rawLog = commands.joined(separator: "\n")
        pythonLog = PythonLogNormalizer.normalize(rawLog)
        historyJSON = encodeHistory(commands: commands)
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

    private func decodeHistoryCommands(from historyJSON: String?) -> [String] {
        guard let historyJSON,
              let data = historyJSON.data(using: .utf8),
              let history = try? JSONDecoder().decode(CommandHistory.self, from: data) else {
            return []
        }
        return history.commands
    }

    private func nextSheetName() -> String {
        "Sheet \(project.sheets.count + 1)"
    }

    private func defaultTableRect(rows: Int, cols: Int, labelBands: LabelBands) -> Rect {
        let count = project.sheets.reduce(0) { $0 + $1.tables.count }
        let offset = Double(count) * 24.0
        let size = gridSize(rows: rows, cols: cols, labelBands: labelBands)
        return Rect(x: 80 + offset,
                    y: 80 + offset,
                    width: Double(size.width),
                    height: Double(size.height))
    }

    private func rectWithGridSize(_ rect: Rect, rows: Int, cols: Int, labelBands: LabelBands) -> Rect {
        let size = gridSize(rows: rows, cols: cols, labelBands: labelBands)
        return Rect(x: rect.x, y: rect.y, width: Double(size.width), height: Double(size.height))
    }

    private func gridSize(rows: Int, cols: Int, labelBands: LabelBands) -> CGSize {
        let metrics = TableGridMetrics(cellSize: cellSize,
                                       bodyRows: rows,
                                       bodyCols: cols,
                                       labelBands: labelBands)
        return CGSize(width: metrics.totalWidth, height: metrics.totalHeight)
    }

    private func syncTableRect(tableId: String) {
        guard let table = table(withId: tableId) else {
            return
        }
        let size = gridSize(rows: table.gridSpec.bodyRows,
                            cols: table.gridSpec.bodyCols,
                            labelBands: table.gridSpec.labelBands)
        let targetWidth = Double(size.width)
        let targetHeight = Double(size.height)
        guard table.rect.width != targetWidth || table.rect.height != targetHeight else {
            return
        }
        let rect = Rect(x: table.rect.x, y: table.rect.y, width: targetWidth, height: targetHeight)
        apply(SetTableRectCommand(tableId: tableId, rect: rect))
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

    private func clearCellSelectionIfInvalid(tableId: String) {
        guard let selection = selectedCell,
              selection.tableId == tableId,
              let table = table(withId: tableId),
              !isSelectionValid(selection, for: table) else {
            return
        }
        selectedCell = nil
    }

    private func isSelectionValid(_ selection: CellSelection, for table: TableModel) -> Bool {
        let grid = table.gridSpec
        let bands = grid.labelBands
        switch selection.region {
        case .body:
            return selection.row >= 0
                && selection.row < grid.bodyRows
                && selection.col >= 0
                && selection.col < grid.bodyCols
        case .topLabels:
            return selection.row >= 0
                && selection.row < bands.topRows
                && selection.col >= 0
                && selection.col < grid.bodyCols
        case .bottomLabels:
            return selection.row >= 0
                && selection.row < bands.bottomRows
                && selection.col >= 0
                && selection.col < grid.bodyCols
        case .leftLabels:
            return selection.row >= 0
                && selection.row < grid.bodyRows
                && selection.col >= 0
                && selection.col < bands.leftCols
        case .rightLabels:
            return selection.row >= 0
                && selection.row < grid.bodyRows
                && selection.col >= 0
                && selection.col < bands.rightCols
        }
    }
}

enum PythonLogNormalizer {
    static func normalize(_ rawLog: String) -> String {
        guard !rawLog.isEmpty else {
            return ""
        }

        let lines = rawLog.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if isTableLine(line),
               index + 1 < lines.count {
                let contextLine = lines[index + 1]
                if isContextLine(contextLine) {
                    var assignments: [String] = []
                    var cursor = index + 2
                    while cursor < lines.count, isIndented(lines[cursor]) {
                        assignments.append(lines[cursor])
                        cursor += 1
                    }
                    if assignments.isEmpty {
                        output.append(line)
                        output.append(contextLine)
                        index = cursor
                        continue
                    }

                    while cursor + 1 < lines.count {
                        if lines[cursor] != line || lines[cursor + 1] != contextLine {
                            break
                        }
                        var nextAssignments: [String] = []
                        var scan = cursor + 2
                        while scan < lines.count, isIndented(lines[scan]) {
                            nextAssignments.append(lines[scan])
                            scan += 1
                        }
                        if nextAssignments.isEmpty {
                            break
                        }
                        assignments.append(contentsOf: nextAssignments)
                        cursor = scan
                    }

                    output.append(line)
                    output.append(contextLine)
                    output.append(contentsOf: assignments)
                    index = cursor
                    continue
                }
            }

            output.append(line)
            index += 1
        }

        return output.joined(separator: "\n")
    }

    private static func isTableLine(_ line: String) -> Bool {
        line.hasPrefix("t = proj.table(")
    }

    private static func isContextLine(_ line: String) -> Bool {
        line.hasPrefix("with formula_context(t):") || line.hasPrefix("with label_context(t,")
    }

    private static func isIndented(_ line: String) -> Bool {
        line.hasPrefix("    ")
    }
}
