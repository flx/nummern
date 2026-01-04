import AppKit
import Combine
import Foundation

struct ReferenceInsertRequest: Equatable {
    let targetTableId: String
    let start: CellSelection
    let end: CellSelection
}

final class CanvasViewModel: ObservableObject {
    @Published private(set) var project: ProjectModel
    @Published private(set) var pythonLog: String
    @Published private(set) var historyJSON: String
    @Published var selectedTableId: String?
    @Published var selectedCell: CellSelection?
    @Published var formulaHighlightState: FormulaHighlightState?
    @Published var activeFormulaEdit: CellSelection?
    @Published var pendingReferenceInsert: ReferenceInsertRequest?

    private let transactionManager = TransactionManager()
    private var seedCommands: [String] = []
    private let cellSize = CanvasGridSizing.cellSize

    init(project: ProjectModel = ProjectModel(), historyJSON: String? = nil) {
        self.project = Self.normalizeTableRects(project)
        self.pythonLog = ""
        self.historyJSON = ""
        self.selectedTableId = nil
        self.selectedCell = nil
        self.formulaHighlightState = nil
        self.activeFormulaEdit = nil
        self.pendingReferenceInsert = nil
        self.seedCommands = decodeHistoryCommands(from: historyJSON)
        rebuildLogs()
    }

    func load(project: ProjectModel, historyJSON: String?) {
        transactionManager.reset()
        seedCommands = decodeHistoryCommands(from: historyJSON)
        self.project = Self.normalizeTableRects(project)
        selectedTableId = nil
        selectedCell = nil
        formulaHighlightState = nil
        activeFormulaEdit = nil
        pendingReferenceInsert = nil
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
        apply(SetTablePositionCommand(tableId: tableId, x: rect.x, y: rect.y))
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

    func minimizeTable(tableId: String) {
        guard let table = table(withId: tableId),
              let bounds = table.bodyContentBounds() else {
            return
        }
        let targetRows = max(CanvasGridSizing.minBodyRows, bounds.maxRow + 1)
        let targetCols = max(CanvasGridSizing.minBodyCols, bounds.maxCol + 1)
        guard targetRows != table.gridSpec.bodyRows || targetCols != table.gridSpec.bodyCols else {
            return
        }
        apply(MinimizeTableCommand(tableId: tableId))
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
        formulaHighlightState = nil
    }

    func setFormulaHighlights(_ state: FormulaHighlightState?) {
        formulaHighlightState = state
    }

    func beginFormulaEdit(_ selection: CellSelection) {
        activeFormulaEdit = selection
    }

    func endFormulaEdit() {
        activeFormulaEdit = nil
        pendingReferenceInsert = nil
    }

    func requestReferenceInsert(start: CellSelection, end: CellSelection) {
        guard let activeFormulaEdit else {
            return
        }
        pendingReferenceInsert = ReferenceInsertRequest(targetTableId: activeFormulaEdit.tableId,
                                                        start: start,
                                                        end: end)
    }

    func consumeReferenceInsert(_ request: ReferenceInsertRequest) {
        if pendingReferenceInsert == request {
            pendingReferenceInsert = nil
        }
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

        if trimmed.hasPrefix("=") {
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

        if let existingFormula = table.formulas[key],
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

    private static func normalizeTableRects(_ project: ProjectModel) -> ProjectModel {
        var updated = project
        for sheetIndex in updated.sheets.indices {
            for tableIndex in updated.sheets[sheetIndex].tables.indices {
                let table = updated.sheets[sheetIndex].tables[tableIndex]
                let metrics = TableGridMetrics(cellSize: CanvasGridSizing.cellSize,
                                               bodyRows: table.gridSpec.bodyRows,
                                               bodyCols: table.gridSpec.bodyCols,
                                               labelBands: table.gridSpec.labelBands)
                let targetWidth = Double(metrics.totalWidth)
                let targetHeight = Double(metrics.totalHeight)
                guard table.rect.width != targetWidth || table.rect.height != targetHeight else {
                    continue
                }
                updated.sheets[sheetIndex].tables[tableIndex].rect = Rect(x: table.rect.x,
                                                                          y: table.rect.y,
                                                                          width: targetWidth,
                                                                          height: targetHeight)
            }
        }
        return updated
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
        let x = table.rect.x
        let y = table.rect.y
        var updated = project
        updated.updateTable(id: tableId) { table in
            table.rect = Rect(x: x, y: y, width: targetWidth, height: targetHeight)
        }
        project = updated
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
        let parsedBlocks = parseBlocks(from: lines)
        var dataEntriesByTable: [String: [DataEntry]] = [:]
        var outputBlocks: [Block] = []

        for block in parsedBlocks {
            switch block {
            case .line(let line):
                if let tableId = dataTableId(from: line) {
                    dataEntriesByTable[tableId, default: []].append(.line(line))
                    continue
                }
                outputBlocks.append(.line(line))
            case .context(let context):
                if context.type == .table {
                    let split = partitionAssignments(context.assignments)
                    if !split.data.isEmpty {
                        dataEntriesByTable[context.tableId, default: []].append(contentsOf: split.data.map { .assignment($0) })
                    }
                    if !split.formula.isEmpty {
                        outputBlocks.append(.context(ContextBlock(tableId: context.tableId,
                                                                  contextLine: context.contextLine,
                                                                  assignments: split.formula,
                                                                  purpose: .formula,
                                                                  type: context.type)))
                    }
                    continue
                }
                outputBlocks.append(.context(ContextBlock(tableId: context.tableId,
                                                          contextLine: context.contextLine,
                                                          assignments: context.assignments,
                                                          purpose: .label,
                                                          type: context.type)))
            }
        }

        var finalBlocks: [Block] = []
        var insertedTables = Set<String>()
        var insertedAliases = Set<String>()
        for block in outputBlocks {
            if case .line(let line) = block, let tableId = addTableId(from: line) {
                append(block, to: &finalBlocks)
                if !insertedAliases.contains(tableId) {
                    append(.line(tableAliasLine(for: tableId)), to: &finalBlocks)
                    insertedAliases.insert(tableId)
                }
                if let dataBlock = dataBlock(for: tableId, entries: dataEntriesByTable[tableId]) {
                    append(dataBlock, to: &finalBlocks)
                    insertedTables.insert(tableId)
                }
                continue
            }
            append(block, to: &finalBlocks)
        }

        for (tableId, entries) in dataEntriesByTable where !insertedTables.contains(tableId) {
            if let dataBlock = dataBlock(for: tableId, entries: entries) {
                append(dataBlock, to: &finalBlocks)
            }
        }

        var outputLines: [String] = []
        for block in finalBlocks {
            switch block {
            case .line(let line):
                outputLines.append(line)
            case .context(let context):
                outputLines.append("t = proj.table(\(PythonLiteralEncoder.encodeString(context.tableId)))")
                outputLines.append(context.contextLine)
                for assignment in context.assignments {
                    outputLines.append("    \(assignment)")
                }
            }
        }

        return outputLines.joined(separator: "\n")
    }

    private enum ContextType {
        case table
        case label
    }

    private enum ContextPurpose: Equatable {
        case data
        case formula
        case label
    }

    private enum DataEntry: Equatable {
        case assignment(String)
        case line(String)
    }

    private struct ContextBlock: Equatable {
        let tableId: String
        let contextLine: String
        let assignments: [String]
        let purpose: ContextPurpose
        let type: ContextType
    }

    private enum Block: Equatable {
        case line(String)
        case context(ContextBlock)
    }

    private static func parseBlocks(from lines: [String]) -> [Block] {
        var blocks: [Block] = []
        var index = 0
        var currentTableId: String?

        while index < lines.count {
            let line = lines[index]
            if let tableId = tableId(fromTableLine: line) {
                currentTableId = tableId
                if index + 1 < lines.count, let context = contextType(from: lines[index + 1]) {
                    let contextLine = lines[index + 1]
                    var assignments: [String] = []
                    var cursor = index + 2
                    while cursor < lines.count, isIndented(lines[cursor]) {
                        assignments.append(stripIndent(lines[cursor]))
                        cursor += 1
                    }
                    blocks.append(.context(ContextBlock(tableId: tableId,
                                                        contextLine: contextLine,
                                                        assignments: assignments,
                                                        purpose: .formula,
                                                        type: context)))
                    index = cursor
                    continue
                }
            }

            if let context = contextType(from: line), let tableId = currentTableId {
                var assignments: [String] = []
                var cursor = index + 1
                while cursor < lines.count, isIndented(lines[cursor]) {
                    assignments.append(stripIndent(lines[cursor]))
                    cursor += 1
                }
                blocks.append(.context(ContextBlock(tableId: tableId,
                                                    contextLine: line,
                                                    assignments: assignments,
                                                    purpose: .formula,
                                                    type: context)))
                index = cursor
                continue
            }

            if let tableId = tableId(fromTableLine: line) {
                currentTableId = tableId
            }

            blocks.append(.line(line))
            index += 1
        }

        return blocks
    }

    private static func dataBlock(for tableId: String, entries: [DataEntry]?) -> Block? {
        guard let entries, !entries.isEmpty else {
            return nil
        }
        var assignments: [String] = []
        for entry in entries {
            switch entry {
            case .assignment(let line):
                assignments.append(line)
            case .line(let line):
                assignments.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        return .context(ContextBlock(tableId: tableId,
                                     contextLine: "with table_context(t):",
                                     assignments: assignments,
                                     purpose: .data,
                                     type: .table))
    }

    private static func tableAliasLine(for tableId: String) -> String {
        "\(tableId) = proj.table(\(PythonLiteralEncoder.encodeString(tableId)))"
    }

    private static func append(_ block: Block, to blocks: inout [Block]) {
        if case .context(let incoming) = block,
           case .context(let last) = blocks.last,
           last.tableId == incoming.tableId,
           last.contextLine == incoming.contextLine,
           last.purpose == incoming.purpose {
            let mergedAssignments = last.assignments + incoming.assignments
            let merged = ContextBlock(tableId: last.tableId,
                                      contextLine: last.contextLine,
                                      assignments: mergedAssignments,
                                      purpose: last.purpose,
                                      type: last.type)
            blocks[blocks.count - 1] = .context(merged)
            return
        }
        blocks.append(block)
    }

    private static func contextType(from line: String) -> ContextType? {
        if line.hasPrefix("with table_context(t):") {
            return .table
        }
        if line.hasPrefix("with label_context(t,") {
            return .label
        }
        return nil
    }

    private static func isIndented(_ line: String) -> Bool {
        line.hasPrefix("    ")
    }

    private static func stripIndent(_ line: String) -> String {
        if line.hasPrefix("    ") {
            return String(line.dropFirst(4))
        }
        return line
    }

    private static func partitionAssignments(_ assignments: [String]) -> (data: [String], formula: [String]) {
        var data: [String] = []
        var formula: [String] = []
        for assignment in assignments {
            guard let rhs = assignment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).last else {
                formula.append(assignment)
                continue
            }
            let value = rhs.trimmingCharacters(in: .whitespaces)
            if isLiteralValue(value) {
                data.append(assignment)
            } else {
                formula.append(assignment)
            }
        }
        return (data, formula)
    }

    private static func isLiteralValue(_ value: String) -> Bool {
        if value == "None" || value == "True" || value == "False" {
            return true
        }
        if isQuotedLiteral(value) {
            return true
        }
        return Double(value) != nil
    }

    private static func isQuotedLiteral(_ value: String) -> Bool {
        guard value.count >= 2 else {
            return false
        }
        let start = value.first
        let end = value.last
        guard start == end, start == "'" || start == "\"" else {
            return false
        }
        return true
    }

    private static func tableId(fromTableLine line: String) -> String? {
        guard line.hasPrefix("t = proj.table(") else {
            return nil
        }
        return extractQuotedValue(from: line, prefix: "t = proj.table(")
    }

    private static func addTableId(from line: String) -> String? {
        guard line.hasPrefix("proj.add_table(") else {
            return nil
        }
        return extractParameterValue(from: line, name: "table_id")
    }

    private static func dataTableId(from line: String) -> String? {
        if let tableId = tableId(from: line, call: ".set_cells(") {
            return tableId
        }
        if let tableId = tableId(from: line, call: ".set_range("),
           let region = setRangeRegion(from: line),
           region == "body" {
            return tableId
        }
        return nil
    }

    private static func tableId(from line: String, call: String) -> String? {
        guard line.contains(call),
              let open = line.range(of: "proj.table(") else {
            return nil
        }
        let segment = line[open.upperBound...]
        return extractQuotedValue(from: String(segment), prefix: "")
    }

    private static func setRangeRegion(from line: String) -> String? {
        guard let rangeArg = extractFirstArgument(from: line, call: ".set_range(") else {
            return nil
        }
        let trimmed = rangeArg.trimmingCharacters(in: .whitespacesAndNewlines)
        let unquoted = extractQuotedValue(from: trimmed, prefix: "") ?? trimmed
        guard let bracket = unquoted.firstIndex(of: "[") else {
            return nil
        }
        return String(unquoted[..<bracket]).lowercased()
    }

    private static func extractFirstArgument(from line: String, call: String) -> String? {
        guard let callRange = line.range(of: call) else {
            return nil
        }
        let afterCall = line[callRange.upperBound...]
        guard let firstComma = afterCall.firstIndex(of: ",") else {
            return nil
        }
        return String(afterCall[..<firstComma])
    }

    private static func extractParameterValue(from line: String, name: String) -> String? {
        guard let range = line.range(of: "\(name)=") else {
            return nil
        }
        let substring = line[range.upperBound...]
        return extractQuotedValue(from: String(substring), prefix: "")
    }

    private static func extractQuotedValue(from line: String, prefix: String) -> String? {
        let trimmed = prefix.isEmpty ? line : String(line.dropFirst(prefix.count))
        guard let firstQuoteIndex = trimmed.firstIndex(where: { $0 == "'" || $0 == "\"" }) else {
            return nil
        }
        let quote = trimmed[firstQuoteIndex]
        let afterQuote = trimmed.index(after: firstQuoteIndex)
        guard let secondQuoteIndex = trimmed[afterQuote...].firstIndex(of: quote) else {
            return nil
        }
        return String(trimmed[afterQuote..<secondQuoteIndex])
    }
}
