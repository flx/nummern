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

        let value: CellValue
        if region == .body {
            let columnType = columnTypeForBody(table: table, col: col)
            guard let parsed = CellValue.fromUserInput(rawValue, columnType: columnType) else {
                return
            }
            value = parsed
        } else {
            value = trimmed.isEmpty ? .empty : .string(trimmed)
        }

        if let existingFormula = table.formulas[key],
           !existingFormula.formula.isEmpty {
            apply(SetFormulaCommand(tableId: tableId,
                                    targetRange: key,
                                    formula: ""),
                  kind: .cellEdit)
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
        guard let table = table(withId: tableId) else {
            return
        }
        let normalizedValues = normalizeRangeValues(table: table,
                                                    region: region,
                                                    startRow: startRow,
                                                    startCol: startCol,
                                                    values: values)
        let endRow = startRow + values.count - 1
        let endCol = startCol + firstRow.count - 1
        let range = RangeParser.rangeString(region: region,
                                            startRow: startRow,
                                            startCol: startCol,
                                            endRow: endRow,
                                            endCol: endCol)
        apply(SetRangeCommand(tableId: tableId, range: range, values: normalizedValues), kind: .general)
    }

    func copySelectionToClipboard() {
        guard let selection = selectedCell,
              let table = table(withId: selection.tableId) else {
            return
        }
        let key = RangeParser.address(region: selection.region, row: selection.row, col: selection.col)
        let text: String
        if selection.region == .body {
            let columnType = columnTypeForBody(table: table, col: selection.col)
            let value = table.cellValues[key] ?? .empty
            text = CellValue.displayString(value, columnType: columnType)
        } else {
            text = table.cellValues[key]?.displayString ?? ""
        }
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
        var commands = seedCommands + transactionManager.allCommands()
        commands = normalizedPreludeCommands(for: project, commands: commands)
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

    private func normalizedPreludeCommands(for project: ProjectModel, commands: [String]) -> [String] {
        let filtered = commands.filter { command in
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            return !isAddSheetCommand(trimmed) && !isAddTableCommand(trimmed)
        }
        let prelude = projectPreludeCommands(project)
        return prelude + filtered
    }

    private func projectPreludeCommands(_ project: ProjectModel) -> [String] {
        var prelude: [String] = []
        for sheet in project.sheets {
            prelude.append(AddSheetCommand(name: sheet.name, sheetId: sheet.id).serializeToPython())
            for table in sheet.tables {
                let command = AddTableCommand(sheetId: sheet.id,
                                              tableId: table.id,
                                              name: table.name,
                                              rect: table.rect,
                                              rows: table.gridSpec.bodyRows,
                                              cols: table.gridSpec.bodyCols,
                                              labels: table.gridSpec.labelBands)
                prelude.append(command.serializeToPython())
            }
        }
        return prelude
    }

    private func isAddSheetCommand(_ line: String) -> Bool {
        line.contains("proj.add_sheet(")
    }

    private func isAddTableCommand(_ line: String) -> Bool {
        line.contains("proj.add_table(")
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

    private func columnTypeForBody(table: TableModel, col: Int) -> ColumnDataType {
        if table.bodyColumnTypes.indices.contains(col) {
            return table.bodyColumnTypes[col]
        }
        return .number
    }

    private func normalizeRangeValues(table: TableModel,
                                      region: GridRegion,
                                      startRow: Int,
                                      startCol: Int,
                                      values: [[CellValue]]) -> [[CellValue]] {
        guard region == .body else {
            return values.map { row in
                row.map { value in
                    switch value {
                    case .string, .empty:
                        return value
                    default:
                        return .string(value.displayString)
                    }
                }
            }
        }
        var normalized: [[CellValue]] = []
        for (rowOffset, rowValues) in values.enumerated() {
            var normalizedRow: [CellValue] = []
            for (colOffset, value) in rowValues.enumerated() {
                let col = startCol + colOffset
                let columnType = columnTypeForBody(table: table, col: col)
                let normalizedValue: CellValue?
                switch columnType {
                case .number:
                    normalizedValue = value
                case .string:
                    switch value {
                    case .string, .empty:
                        normalizedValue = value
                    default:
                        normalizedValue = .string(value.displayString)
                    }
                case .currency, .percentage, .date, .time:
                    switch value {
                    case .string(let raw):
                        normalizedValue = CellValue.fromUserInput(raw, columnType: columnType)
                    case .empty:
                        normalizedValue = .empty
                    default:
                        normalizedValue = value
                    }
                }

                if let normalizedValue {
                    normalizedRow.append(normalizedValue)
                } else {
                    let row = startRow + rowOffset
                    let key = RangeParser.address(region: region, row: row, col: col)
                    normalizedRow.append(table.cellValues[key] ?? .empty)
                }
            }
            normalized.append(normalizedRow)
        }
        return normalized
    }

    func selectedTable() -> TableModel? {
        guard let selectedTableId else {
            return nil
        }
        return table(withId: selectedTableId)
    }

    func setBodyColumnType(tableId: String, col: Int, type: ColumnDataType) {
        guard col >= 0 else {
            return
        }
        apply(SetColumnTypeCommand(tableId: tableId, col: col, columnType: type), kind: .general)
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
                if case .table = context.context {
                    let split = partitionAssignments(context.assignments)
                    if !split.data.isEmpty {
                        dataEntriesByTable[context.tableId, default: []].append(contentsOf: split.data.map { .assignment($0) })
                    }
                    if !split.formula.isEmpty {
                        outputBlocks.append(.context(ContextBlock(tableId: context.tableId,
                                                                  context: .table,
                                                                  assignments: split.formula,
                                                                  purpose: .formula)))
                    }
                    continue
                }
                outputBlocks.append(.context(ContextBlock(tableId: context.tableId,
                                                          context: context.context,
                                                          assignments: context.assignments,
                                                          purpose: .label)))
            }
        }

        var finalBlocks: [Block] = []
        var insertedTables = Set<String>()
        for block in outputBlocks {
            if case .line(let line) = block, let tableId = addTableId(from: line) {
                let normalizedLine = normalizeAddTableLine(line, tableId: tableId)
                append(.line(normalizedLine), to: &finalBlocks)
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
                outputLines.append(contextLine(for: context))
                for assignment in context.assignments {
                    outputLines.append("    \(assignment)")
                }
            }
        }

        return outputLines.joined(separator: "\n")
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
        let context: ContextKind
        let assignments: [String]
        let purpose: ContextPurpose
    }

    private enum Block: Equatable {
        case line(String)
        case context(ContextBlock)
    }

    private enum ContextKind: Equatable {
        case table
        case label(String)
    }

    private static func parseBlocks(from lines: [String]) -> [Block] {
        var blocks: [Block] = []
        var index = 0
        var currentTableId: String?
        var aliasToTableId: [String: String] = [:]

        while index < lines.count {
            let line = lines[index]
            if let aliasMapping = tableAliasMapping(from: line) {
                aliasToTableId[aliasMapping.alias] = aliasMapping.tableId
                currentTableId = aliasMapping.tableId
                if aliasMapping.kind == .tableRef,
                   index + 1 < lines.count,
                   let contextKind = contextKind(from: lines[index + 1]),
                   let contextTableId = contextTableId(from: lines[index + 1],
                                                      aliasToTableId: aliasToTableId,
                                                      fallback: aliasMapping.tableId) {
                    var assignments: [String] = []
                    var cursor = index + 2
                    while cursor < lines.count, isIndented(lines[cursor]) {
                        assignments.append(stripIndent(lines[cursor]))
                        cursor += 1
                    }
                    blocks.append(.context(ContextBlock(tableId: contextTableId,
                                                        context: contextKind,
                                                        assignments: assignments,
                                                        purpose: .formula)))
                    index = cursor
                    continue
                }
            }

            if let tableId = tableId(fromTableLine: line) {
                currentTableId = tableId
            }

            if let tableId = addTableId(from: line) {
                currentTableId = tableId
                aliasToTableId[tableId] = tableId
            }

            if let contextKind = contextKind(from: line),
               let tableId = contextTableId(from: line,
                                            aliasToTableId: aliasToTableId,
                                            fallback: currentTableId) {
                var assignments: [String] = []
                var cursor = index + 1
                while cursor < lines.count, isIndented(lines[cursor]) {
                    assignments.append(stripIndent(lines[cursor]))
                    cursor += 1
                }
                blocks.append(.context(ContextBlock(tableId: tableId,
                                                    context: contextKind,
                                                    assignments: assignments,
                                                    purpose: .formula)))
                index = cursor
                continue
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
                                     context: .table,
                                     assignments: assignments,
                                     purpose: .data))
    }

    private static func normalizeAddTableLine(_ line: String, tableId: String) -> String {
        if assignmentAlias(from: line, call: "proj.add_table(") != nil {
            return line
        }
        return "\(tableId) = \(line)"
    }

    private static func append(_ block: Block, to blocks: inout [Block]) {
        if case .context(let incoming) = block,
           case .context(let last) = blocks.last,
           last.tableId == incoming.tableId,
           last.context == incoming.context,
           last.purpose == incoming.purpose {
            let mergedAssignments = last.assignments + incoming.assignments
            let merged = ContextBlock(tableId: last.tableId,
                                      context: last.context,
                                      assignments: mergedAssignments,
                                      purpose: last.purpose)
            blocks[blocks.count - 1] = .context(merged)
            return
        }
        blocks.append(block)
    }

    private static func contextLine(for context: ContextBlock) -> String {
        switch context.context {
        case .table:
            return "with table_context(\(context.tableId)):"
        case .label(let region):
            let encodedRegion = PythonLiteralEncoder.encodeString(region)
            return "with label_context(\(context.tableId), \(encodedRegion)):"
        }
    }

    private static func contextKind(from line: String) -> ContextKind? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("with table_context(") {
            return .table
        }
        if trimmed.hasPrefix("with label_context("),
           let region = labelRegion(from: trimmed) {
            return .label(region)
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
        guard let open = line.range(of: "proj.table(") else {
            return nil
        }
        let segment = line[open.upperBound...]
        return extractQuotedValue(from: String(segment), prefix: "")
    }

    private static func addTableId(from line: String) -> String? {
        guard line.contains("proj.add_table(") else {
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

    private static func tableAliasMapping(from line: String) -> (alias: String, tableId: String, kind: AliasKind)? {
        if let alias = assignmentAlias(from: line, call: "proj.table("),
           let tableId = tableId(fromTableLine: line) {
            return (alias: alias, tableId: tableId, kind: .tableRef)
        }
        if let alias = assignmentAlias(from: line, call: "proj.add_table(") {
            let tableId = extractParameterValue(from: line, name: "table_id") ?? alias
            return (alias: alias, tableId: tableId, kind: .addTable)
        }
        return nil
    }

    private static func assignmentAlias(from line: String, call: String) -> String? {
        let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return nil
        }
        let lhs = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let rhs = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard rhs.hasPrefix(call), !lhs.isEmpty else {
            return nil
        }
        return lhs
    }

    private static func contextTableId(from line: String,
                                       aliasToTableId: [String: String],
                                       fallback: String?) -> String? {
        guard let alias = contextAlias(from: line) else {
            return fallback
        }
        if let mapped = aliasToTableId[alias] {
            return mapped
        }
        return fallback ?? alias
    }

    private static func contextAlias(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("with table_context(") {
            return extractContextArgument(from: trimmed)
        }
        if trimmed.hasPrefix("with label_context(") {
            return extractContextArgument(from: trimmed)
        }
        return nil
    }

    private static func extractContextArgument(from line: String) -> String? {
        guard let open = line.firstIndex(of: "(") else {
            return nil
        }
        let afterOpen = line.index(after: open)
        let remainder = line[afterOpen...]
        let endIndex = remainder.firstIndex(of: ",") ?? remainder.firstIndex(of: ")") ?? line.endIndex
        let value = remainder[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func labelRegion(from line: String) -> String? {
        guard let comma = line.firstIndex(of: ",") else {
            return nil
        }
        let afterComma = line[line.index(after: comma)...]
        return extractQuotedValue(from: String(afterComma), prefix: "")
    }

    private enum AliasKind {
        case tableRef
        case addTable
    }
}
