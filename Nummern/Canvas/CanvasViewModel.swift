import AppKit
import Combine
import Foundation

struct ReferenceInsertRequest: Equatable {
    let targetTableId: String
    let start: CellSelection
    let end: CellSelection
}

struct EditRequest: Equatable {
    let tableId: String
    let selection: CellSelection
    let initialText: String?
    let applyRange: TableRangeSelection?
}

final class CanvasViewModel: ObservableObject {
    @Published private(set) var project: ProjectModel
    @Published private(set) var pythonLog: String
    @Published private(set) var historyJSON: String
    @Published var selectedTableId: String?
    @Published var selectedChartId: String?
    @Published var selectedCell: CellSelection?
    @Published var selectedRanges: [TableRangeSelection]
    @Published var formulaHighlightState: FormulaHighlightState?
    @Published var activeFormulaEdit: CellSelection?
    @Published var pendingReferenceInsert: ReferenceInsertRequest?
    @Published var pendingEditRequest: EditRequest?
    @Published var needsCanvasKeyFocus: Bool

    private let transactionManager = TransactionManager()
    private var seedCommands: [String] = []
    private let cellSize = CanvasGridSizing.cellSize
    private var selectionAnchor: CellSelection?
    var undoManager: UndoManager?

    init(project: ProjectModel = ProjectModel(), historyJSON: String? = nil) {
        self.project = Self.normalizeTableRects(project)
        self.pythonLog = ""
        self.historyJSON = ""
        self.selectedTableId = nil
        self.selectedChartId = nil
        self.selectedCell = nil
        self.selectedRanges = []
        self.formulaHighlightState = nil
        self.activeFormulaEdit = nil
        self.pendingReferenceInsert = nil
        self.pendingEditRequest = nil
        self.needsCanvasKeyFocus = false
        self.seedCommands = decodeHistoryCommands(from: historyJSON)
        rebuildLogs()
    }

    func setUndoManager(_ manager: UndoManager?) {
        undoManager = manager
    }

    func load(project: ProjectModel, historyJSON: String?) {
        transactionManager.reset()
        seedCommands = decodeHistoryCommands(from: historyJSON)
        self.project = Self.normalizeTableRects(project)
        selectedTableId = nil
        selectedChartId = nil
        selectedCell = nil
        selectedRanges = []
        formulaHighlightState = nil
        activeFormulaEdit = nil
        pendingReferenceInsert = nil
        pendingEditRequest = nil
        needsCanvasKeyFocus = false
        selectionAnchor = nil
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

    @discardableResult
    func addChart(toSheetId sheetId: String,
                  tableId: String,
                  chartType: ChartType = .line,
                  valueRange: String? = nil,
                  labelRange: String? = nil) -> ChartModel? {
        guard let table = table(withId: tableId) else {
            return nil
        }
        let chartId = project.nextChartId()
        let chartName = chartId
        let resolvedRange: String
        if let valueRange {
            resolvedRange = valueRange
        } else {
            let endRow = max(0, min(table.gridSpec.bodyRows - 1, 4))
            resolvedRange = RangeParser.rangeString(region: .body,
                                                    startRow: 0,
                                                    startCol: 0,
                                                    endRow: endRow,
                                                    endCol: 0)
        }
        let resolvedLabelRange = labelRange
        let rect = defaultChartRect()
        let command = AddChartCommand(sheetId: sheetId,
                                      chartId: chartId,
                                      name: chartName,
                                      rect: rect,
                                      chartType: chartType,
                                      tableId: tableId,
                                      valueRange: resolvedRange,
                                      labelRange: resolvedLabelRange,
                                      title: "",
                                      xAxisTitle: "",
                                      yAxisTitle: "",
                                      showLegend: true)
        apply(command)
        return chart(withId: chartId)
    }

    @discardableResult
    func addChartForSelection(toSheetId sheetId: String,
                              chartType: ChartType = .line) -> ChartModel? {
        if let selection = activeSelectionRange(),
           selection.region == .body,
           let table = table(withId: selection.tableId) {
            guard let ranges = chartRanges(for: selection, table: table, chartType: chartType) else {
                return nil
            }
            return addChart(toSheetId: sheetId,
                            tableId: selection.tableId,
                            chartType: chartType,
                            valueRange: ranges.valueRange,
                            labelRange: ranges.labelRange)
        }
        guard let table = selectedTable() else {
            return nil
        }
        guard let ranges = chartRangesForTable(table, chartType: chartType) else {
            return nil
        }
        return addChart(toSheetId: sheetId,
                        tableId: table.id,
                        chartType: chartType,
                        valueRange: ranges.valueRange,
                        labelRange: ranges.labelRange)
    }

    @discardableResult
    func createSummaryTable(sourceTableId: String,
                            sourceRange: String? = nil,
                            groupBy: [Int],
                            values: [SummaryValueSpec]) -> TableModel? {
        guard let sourceTable = table(withId: sourceTableId),
              let sheetId = sheetId(containingTableId: sourceTableId) else {
            return nil
        }
        let maxCol = max(0, sourceTable.gridSpec.bodyCols - 1)
        let filteredGroupBy = groupBy.filter { $0 >= 0 && $0 <= maxCol }
        let filteredValues = values.filter { $0.column >= 0 && $0.column <= maxCol }
        guard !filteredValues.isEmpty else {
            return nil
        }
        let tableId = project.nextTableId()
        let tableName = tableId
        let summaryRows = estimateSummaryRowCount(sourceTable: sourceTable,
                                                  groupBy: filteredGroupBy,
                                                  sourceRange: sourceRange)
        let summaryCols = max(CanvasGridSizing.minBodyCols, filteredGroupBy.count + filteredValues.count)
        let baseRect = defaultTableRect(rows: summaryRows, cols: summaryCols, labelBands: .zero)
        let sizedRect = rectWithGridSize(baseRect, rows: summaryRows, cols: summaryCols, labelBands: .zero)
        let command = CreateSummaryTableCommand(sheetId: sheetId,
                                                tableId: tableId,
                                                name: tableName,
                                                rect: sizedRect,
                                                sourceTableId: sourceTableId,
                                                sourceRange: sourceRange,
                                                groupBy: filteredGroupBy,
                                                values: filteredValues,
                                                rows: summaryRows,
                                                cols: summaryCols)
        apply(command)
        return table(withId: tableId)
    }

    func moveTable(tableId: String, to rect: Rect) {
        apply(SetTablePositionCommand(tableId: tableId, x: rect.x, y: rect.y))
    }

    func moveChart(chartId: String, to rect: Rect) {
        apply(SetChartPositionCommand(chartId: chartId, x: rect.x, y: rect.y))
    }

    func updateTableRect(tableId: String, rect: Rect) {
        apply(SetTableRectCommand(tableId: tableId, rect: rect))
    }

    func updateChartRect(chartId: String, rect: Rect) {
        apply(SetChartRectCommand(chartId: chartId, rect: rect))
    }

    func setChartType(chartId: String, chartType: ChartType) {
        apply(UpdateChartCommand(chartId: chartId, chartType: chartType))
    }

    func setChartValueRange(chartId: String, valueRange: String) {
        apply(UpdateChartCommand(chartId: chartId, valueRange: valueRange))
    }

    func setChartLabelRange(chartId: String, labelRange: String?) {
        let update: ChartLabelRangeUpdate = {
            if let labelRange, !labelRange.isEmpty {
                return .set(labelRange)
            }
            return .clear
        }()
        apply(UpdateChartCommand(chartId: chartId, labelRange: update))
    }

    func setChartTitle(chartId: String, title: String) {
        apply(UpdateChartCommand(chartId: chartId, title: title))
    }

    func setChartXAxisTitle(chartId: String, title: String) {
        apply(UpdateChartCommand(chartId: chartId, xAxisTitle: title))
    }

    func setChartYAxisTitle(chartId: String, title: String) {
        apply(UpdateChartCommand(chartId: chartId, yAxisTitle: title))
    }

    func setChartShowLegend(chartId: String, showLegend: Bool) {
        apply(UpdateChartCommand(chartId: chartId, showLegend: showLegend))
    }

    func setLabelBands(tableId: String, labelBands: LabelBands) {
        apply(SetLabelBandsCommand(tableId: tableId, labelBands: labelBands))
        syncTableRect(tableId: tableId)
        clearSelectionIfInvalid(tableId: tableId)
    }

    func setBodySize(tableId: String, rows: Int, cols: Int) {
        let safeRows = max(CanvasGridSizing.minBodyRows, rows)
        let safeCols = max(CanvasGridSizing.minBodyCols, cols)
        apply(ResizeTableCommand(tableId: tableId, rows: safeRows, cols: safeCols))
        syncTableRect(tableId: tableId)
        clearSelectionIfInvalid(tableId: tableId)
    }

    func setBodyRows(tableId: String, rows: Int) {
        let safeRows = max(CanvasGridSizing.minBodyRows, rows)
        apply(ResizeTableCommand(tableId: tableId, rows: safeRows))
        syncTableRect(tableId: tableId)
        clearSelectionIfInvalid(tableId: tableId)
    }

    func setBodyCols(tableId: String, cols: Int) {
        let safeCols = max(CanvasGridSizing.minBodyCols, cols)
        apply(ResizeTableCommand(tableId: tableId, cols: safeCols))
        syncTableRect(tableId: tableId)
        clearSelectionIfInvalid(tableId: tableId)
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
        selectedChartId = nil
        selectedCell = nil
        selectedRanges = []
        formulaHighlightState = nil
        selectionAnchor = nil
        requestCanvasKeyFocus()
    }

    func selectChart(_ chartId: String) {
        selectedChartId = chartId
        selectedTableId = nil
        selectedCell = nil
        selectedRanges = []
        formulaHighlightState = nil
        selectionAnchor = nil
        requestCanvasKeyFocus()
    }

    func selectCell(_ selection: CellSelection) {
        replaceSelection(with: TableRangeSelection(cell: selection),
                         activeCell: selection,
                         anchor: selection)
    }

    func replaceSelection(with range: TableRangeSelection,
                          activeCell: CellSelection,
                          anchor: CellSelection? = nil) {
        guard !range.tableId.isEmpty else {
            return
        }
        selectedTableId = range.tableId
        selectedChartId = nil
        selectedCell = activeCell
        selectedRanges = [range.normalized]
        selectionAnchor = anchor ?? activeCell
        if !isEditing() {
            requestCanvasKeyFocus()
        }
    }

    func addSelection(range: TableRangeSelection, activeCell: CellSelection) {
        if selectedRanges.isEmpty || selectedTableId != range.tableId {
            replaceSelection(with: range, activeCell: activeCell, anchor: range.startCell)
            return
        }
        let normalized = range.normalized
        if !selectedRanges.contains(normalized) {
            selectedRanges.append(normalized)
        }
        selectedTableId = range.tableId
        selectedChartId = nil
        selectedCell = activeCell
        selectionAnchor = activeCell
        requestCanvasKeyFocus()
    }

    func toggleSelection(cell: CellSelection) {
        let range = TableRangeSelection(cell: cell).normalized
        if selectedRanges.isEmpty || selectedTableId != cell.tableId {
            replaceSelection(with: range, activeCell: cell, anchor: cell)
            return
        }
        if let index = selectedRanges.firstIndex(of: range) {
            selectedRanges.remove(at: index)
            if selectedRanges.isEmpty {
                selectedCell = nil
                selectionAnchor = nil
                selectedTableId = nil
            } else {
                selectedCell = selectedRanges.last?.endCell
            }
        } else {
            selectedRanges.append(range)
            selectedCell = cell
            selectionAnchor = cell
        }
        selectedTableId = cell.tableId
        selectedChartId = nil
        requestCanvasKeyFocus()
    }

    func extendSelection(to cell: CellSelection, addRange: Bool) {
        guard let anchor = selectionAnchor,
              anchor.tableId == cell.tableId,
              anchor.region == cell.region else {
            replaceSelection(with: TableRangeSelection(cell: cell),
                             activeCell: cell,
                             anchor: cell)
            return
        }
        let range = TableRangeSelection(tableId: cell.tableId,
                                        region: cell.region,
                                        startRow: anchor.row,
                                        startCol: anchor.col,
                                        endRow: cell.row,
                                        endCol: cell.col)
        if addRange {
            addSelection(range: range, activeCell: cell)
        } else {
            replaceSelection(with: range, activeCell: cell, anchor: anchor)
        }
    }

    func clearCellSelection() {
        selectedCell = nil
        selectedRanges = []
        selectionAnchor = nil
    }

    func clearSelection() {
        selectedCell = nil
        selectedRanges = []
        selectedTableId = nil
        selectedChartId = nil
        formulaHighlightState = nil
        selectionAnchor = nil
    }

    func requestCanvasKeyFocus() {
        needsCanvasKeyFocus = true
    }

    func consumeCanvasKeyFocus() {
        needsCanvasKeyFocus = false
    }

    func activeSelectionRange() -> TableRangeSelection? {
        if let range = selectedRanges.last {
            return range
        }
        if let cell = selectedCell {
            return TableRangeSelection(cell: cell)
        }
        return nil
    }

    func selectionRanges(for tableId: String) -> [TableRangeSelection] {
        selectedRanges.filter { $0.tableId == tableId }
    }

    func activeRange(for tableId: String) -> TableRangeSelection? {
        selectedRanges.last { $0.tableId == tableId }
    }

    func requestEdit(at selection: CellSelection,
                     initialText: String? = nil,
                     applyRange: TableRangeSelection? = nil) {
        pendingEditRequest = EditRequest(tableId: selection.tableId,
                                         selection: selection,
                                         initialText: initialText,
                                         applyRange: applyRange)
    }

    func consumeEditRequest(_ request: EditRequest) {
        if pendingEditRequest == request {
            pendingEditRequest = nil
        }
    }

    func isEditing() -> Bool {
        activeFormulaEdit != nil
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
        requestCanvasKeyFocus()
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
        guard !isReadOnlyTable(tableId: tableId) else {
            return
        }
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

    func setRangeValue(range: TableRangeSelection, rawValue: String) {
        guard !isReadOnlyTable(tableId: range.tableId),
              let table = table(withId: range.tableId) else {
            return
        }
        let normalized = range.normalized
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("=") {
            apply(SetFormulaCommand(tableId: range.tableId,
                                    targetRange: normalized.rangeString(),
                                    formula: trimmed),
                  kind: .cellEdit)
            return
        }
        let rowCount = normalized.endRow - normalized.startRow + 1
        let colCount = normalized.endCol - normalized.startCol + 1
        guard rowCount > 0, colCount > 0 else {
            return
        }
        var values: [[CellValue]] = []
        if normalized.region == .body {
            var columnValues: [CellValue] = []
            for col in normalized.startCol...normalized.endCol {
                let columnType = columnTypeForBody(table: table, col: col)
                let value: CellValue
                if trimmed.isEmpty {
                    value = .empty
                } else if let parsed = CellValue.fromUserInput(rawValue, columnType: columnType) {
                    value = parsed
                } else {
                    return
                }
                columnValues.append(value)
            }
            values = Array(repeating: columnValues, count: rowCount)
        } else {
            let value: CellValue = trimmed.isEmpty ? .empty : .string(trimmed)
            let row = Array(repeating: value, count: colCount)
            values = Array(repeating: row, count: rowCount)
        }
        setRange(tableId: range.tableId,
                 region: normalized.region,
                 startRow: normalized.startRow,
                 startCol: normalized.startCol,
                 values: values)
    }

    func setRange(tableId: String,
                  region: GridRegion,
                  startRow: Int,
                  startCol: Int,
                  values: [[CellValue]]) {
        guard !isReadOnlyTable(tableId: tableId) else {
            return
        }
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
        guard let range = activeSelectionRange(),
              let table = table(withId: range.tableId) else {
            return
        }
        let normalized = range.normalized
        var rows: [String] = []
        for row in normalized.startRow...normalized.endRow {
            var columns: [String] = []
            for col in normalized.startCol...normalized.endCol {
                let selection = CellSelection(tableId: range.tableId,
                                              region: range.region,
                                              row: row,
                                              col: col)
                columns.append(displayValue(for: selection, table: table))
            }
            rows.append(columns.joined(separator: "\t"))
        }
        let text = rows.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func pasteFromClipboard() {
        guard let range = activeSelectionRange(),
              let text = NSPasteboard.general.string(forType: .string),
              !text.isEmpty else {
            return
        }
        guard !isReadOnlyTable(tableId: range.tableId) else {
            return
        }
        let normalized = range.normalized
        let values = ClipboardParser.values(from: text, region: range.region)
        guard !values.isEmpty, !(values.first?.isEmpty ?? true) else {
            return
        }
        setRange(tableId: range.tableId,
                 region: range.region,
                 startRow: normalized.startRow,
                 startCol: normalized.startCol,
                 values: values)
    }

    func clearSelectionValues() {
        let ranges = selectedRanges.isEmpty ? activeSelectionRange().map { [$0] } ?? [] : selectedRanges
        guard let tableId = ranges.first?.tableId,
              let table = table(withId: tableId),
              !isReadOnlyTable(tableId: tableId) else {
            return
        }
        var formulasToClear: [String] = []
        for key in table.formulas.keys {
            guard let parsed = try? RangeParser.parse(key) else {
                continue
            }
            if ranges.contains(where: { rangeIntersects(range: $0, address: parsed) }) {
                formulasToClear.append(key)
            }
        }
        var cellMap: [String: CellValue] = [:]
        for range in ranges {
            let normalized = range.normalized
            for row in normalized.startRow...normalized.endRow {
                for col in normalized.startCol...normalized.endCol {
                    let key = RangeParser.address(region: range.region, row: row, col: col)
                    cellMap[key] = .empty
                }
            }
        }
        var commands: [any Command] = []
        for key in formulasToClear {
            commands.append(SetFormulaCommand(tableId: tableId, targetRange: key, formula: ""))
        }
        if !cellMap.isEmpty {
            commands.append(SetCellsCommand(tableId: tableId, cellMap: cellMap))
        }
        guard !commands.isEmpty else {
            return
        }
        if commands.count == 1, let command = commands.first {
            apply(command, kind: .cellEdit)
        } else {
            apply(CommandBatch(commands: commands), kind: .cellEdit)
        }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if isEditing() {
            return false
        }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if flags.contains(.command) {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "c":
                    copySelectionToClipboard()
                    return true
                case "v":
                    pasteFromClipboard()
                    return true
                case "z":
                    if flags.contains(.shift) {
                        undoManager?.redo()
                    } else {
                        undoManager?.undo()
                    }
                    return true
                default:
                    break
                }
            }
        }

        let hasSelection = selectedCell != nil || !selectedRanges.isEmpty

        switch event.keyCode {
        case 53: // Escape
            clearSelection()
            return true
        case 36, 76: // Return, Enter
            if flags.contains(.shift) {
                if hasSelection {
                    moveSelection(deltaRow: -1,
                                  deltaCol: 0,
                                  extend: false,
                                  addRange: false)
                    return true
                }
                return false
            }
            if let selection = selectedCell ?? activeSelectionRange()?.endCell {
                replaceSelection(with: TableRangeSelection(cell: selection),
                                 activeCell: selection,
                                 anchor: selection)
                requestEdit(at: selection, initialText: nil)
                return true
            }
        case 48: // Tab
            guard hasSelection else {
                return false
            }
            let direction: (row: Int, col: Int) = flags.contains(.shift) ? (0, -1) : (0, 1)
            moveSelection(deltaRow: direction.row,
                          deltaCol: direction.col,
                          extend: false,
                          addRange: false)
            return true
        case 123: // Left
            guard hasSelection else {
                return false
            }
            moveSelection(deltaRow: 0,
                          deltaCol: -1,
                          extend: flags.contains(.shift),
                          addRange: flags.contains(.shift) && flags.contains(.command))
            return true
        case 124: // Right
            guard hasSelection else {
                return false
            }
            moveSelection(deltaRow: 0,
                          deltaCol: 1,
                          extend: flags.contains(.shift),
                          addRange: flags.contains(.shift) && flags.contains(.command))
            return true
        case 125: // Down
            guard hasSelection else {
                return false
            }
            moveSelection(deltaRow: 1,
                          deltaCol: 0,
                          extend: flags.contains(.shift),
                          addRange: flags.contains(.shift) && flags.contains(.command))
            return true
        case 126: // Up
            guard hasSelection else {
                return false
            }
            moveSelection(deltaRow: -1,
                          deltaCol: 0,
                          extend: flags.contains(.shift),
                          addRange: flags.contains(.shift) && flags.contains(.command))
            return true
        case 51, 117: // Delete, Forward delete
            guard hasSelection else {
                return false
            }
            clearSelectionValues()
            return true
        default:
            break
        }

        guard !flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
              let chars = event.characters, !chars.isEmpty else {
            return false
        }
        if let selection = selectedCell ?? activeSelectionRange()?.endCell {
            let applyRange = activeSelectionRange().flatMap { range in
                range.isSingleCell ? nil : range
            }
            requestEdit(at: selection, initialText: chars, applyRange: applyRange)
            return true
        }
        return false
    }

    private func apply(_ command: any Command, kind: TransactionKind = .general) {
        let previous = project
        transactionManager.begin(kind: kind)
        transactionManager.record(command)
        transactionManager.commit()
        var updated = project
        command.apply(to: &updated)
        project = updated
        rebuildLogs()
        if let undoManager,
           let inverse = command.invert(previous: previous) {
            undoManager.registerUndo(withTarget: self) { target in
                target.apply(inverse, kind: kind)
            }
        }
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
            return !isAddSheetCommand(trimmed) && !isAddTableCommand(trimmed) && !isAddChartCommand(trimmed)
        }
        let prelude = projectPreludeCommands(project)
        return prelude + filtered
    }

    private func projectPreludeCommands(_ project: ProjectModel) -> [String] {
        var prelude: [String] = []
        for sheet in project.sheets {
            prelude.append(AddSheetCommand(name: sheet.name, sheetId: sheet.id).serializeToPython())
            for table in sheet.tables {
                if let summarySpec = table.summarySpec {
                    let command = CreateSummaryTableCommand(sheetId: sheet.id,
                                                            tableId: table.id,
                                                            name: table.name,
                                                            rect: table.rect,
                                                            sourceTableId: summarySpec.sourceTableId,
                                                            sourceRange: summarySpec.sourceRange,
                                                            groupBy: summarySpec.groupBy,
                                                            values: summarySpec.values,
                                                            rows: table.gridSpec.bodyRows,
                                                            cols: table.gridSpec.bodyCols)
                    prelude.append(command.serializeToPython())
                } else {
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
            for chart in sheet.charts {
                let command = AddChartCommand(sheetId: sheet.id,
                                              chartId: chart.id,
                                              name: chart.name,
                                              rect: chart.rect,
                                              chartType: chart.chartType,
                                              tableId: chart.tableId,
                                              valueRange: chart.valueRange,
                                              labelRange: chart.labelRange,
                                              title: chart.title,
                                              xAxisTitle: chart.xAxisTitle,
                                              yAxisTitle: chart.yAxisTitle,
                                              showLegend: chart.showLegend)
                prelude.append(command.serializeToPython())
            }
        }
        return prelude
    }

    private func isAddSheetCommand(_ line: String) -> Bool {
        line.contains("proj.add_sheet(")
    }

    private func isAddTableCommand(_ line: String) -> Bool {
        line.contains("proj.add_table(") || line.contains("proj.add_summary_table(")
    }

    private func isAddChartCommand(_ line: String) -> Bool {
        line.contains("proj.add_chart(")
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

    private func defaultChartRect() -> Rect {
        let count = project.sheets.reduce(0) { $0 + $1.tables.count + $1.charts.count }
        let offset = Double(count) * 24.0
        return Rect(x: 80 + offset,
                    y: 80 + offset,
                    width: Double(CanvasChartSizing.defaultSize.width),
                    height: Double(CanvasChartSizing.defaultSize.height))
    }

    private struct ChartRanges {
        let valueRange: String
        let labelRange: String?
    }

    private func chartRanges(for selection: TableRangeSelection,
                             table: TableModel,
                             chartType: ChartType) -> ChartRanges? {
        let normalized = selection.normalized
        guard normalized.region == .body else {
            return nil
        }
        let rowStart = max(0, normalized.startRow)
        let rowEnd = min(normalized.endRow, max(0, table.gridSpec.bodyRows - 1))
        let colStart = max(0, normalized.startCol)
        let colEnd = min(normalized.endCol, max(0, table.gridSpec.bodyCols - 1))
        guard rowStart <= rowEnd, colStart <= colEnd else {
            return nil
        }
        if colStart == colEnd {
            let valueRange = RangeParser.rangeString(region: .body,
                                                     startRow: rowStart,
                                                     startCol: colStart,
                                                     endRow: rowEnd,
                                                     endCol: colEnd)
            return ChartRanges(valueRange: valueRange, labelRange: nil)
        }
        let categoryCol = colStart
        let valueStart = colStart + 1
        let valueEnd: Int
        if chartType == .pie {
            valueEnd = min(valueStart, colEnd)
        } else {
            valueEnd = colEnd
        }
        if valueStart > colEnd {
            let valueRange = RangeParser.rangeString(region: .body,
                                                     startRow: rowStart,
                                                     startCol: categoryCol,
                                                     endRow: rowEnd,
                                                     endCol: categoryCol)
            return ChartRanges(valueRange: valueRange, labelRange: nil)
        }
        let valueRange = RangeParser.rangeString(region: .body,
                                                 startRow: rowStart,
                                                 startCol: valueStart,
                                                 endRow: rowEnd,
                                                 endCol: valueEnd)
        let labelRange = RangeParser.rangeString(region: .body,
                                                 startRow: rowStart,
                                                 startCol: categoryCol,
                                                 endRow: rowEnd,
                                                 endCol: categoryCol)
        return ChartRanges(valueRange: valueRange, labelRange: labelRange)
    }

    private func chartRangesForTable(_ table: TableModel,
                                     chartType: ChartType) -> ChartRanges? {
        guard table.gridSpec.bodyRows > 0, table.gridSpec.bodyCols > 0 else {
            return nil
        }
        let rowStart = 0
        let rowEnd = max(0, table.gridSpec.bodyRows - 1)
        let bodyCols = table.gridSpec.bodyCols
        if hasLeftLabelData(table) {
            let valueStart = 0
            let valueEnd = chartType == .pie ? 0 : max(0, bodyCols - 1)
            let valueRange = RangeParser.rangeString(region: .body,
                                                     startRow: rowStart,
                                                     startCol: valueStart,
                                                     endRow: rowEnd,
                                                     endCol: valueEnd)
            let labelRange = RangeParser.rangeString(region: .leftLabels,
                                                     startRow: rowStart,
                                                     startCol: 0,
                                                     endRow: rowEnd,
                                                     endCol: 0)
            return ChartRanges(valueRange: valueRange, labelRange: labelRange)
        }

        if bodyCols == 1 {
            let valueRange = RangeParser.rangeString(region: .body,
                                                     startRow: rowStart,
                                                     startCol: 0,
                                                     endRow: rowEnd,
                                                     endCol: 0)
            return ChartRanges(valueRange: valueRange, labelRange: nil)
        }
        let valueStart = 1
        let valueEnd = chartType == .pie ? 1 : max(1, bodyCols - 1)
        let valueRange = RangeParser.rangeString(region: .body,
                                                 startRow: rowStart,
                                                 startCol: valueStart,
                                                 endRow: rowEnd,
                                                 endCol: valueEnd)
        let labelRange = RangeParser.rangeString(region: .body,
                                                 startRow: rowStart,
                                                 startCol: 0,
                                                 endRow: rowEnd,
                                                 endCol: 0)
        return ChartRanges(valueRange: valueRange, labelRange: labelRange)
    }

    private func hasLeftLabelData(_ table: TableModel) -> Bool {
        guard table.gridSpec.labelBands.leftCols > 0 else {
            return false
        }
        let rows = table.gridSpec.bodyRows
        let cols = table.gridSpec.labelBands.leftCols
        for row in 0..<rows {
            for col in 0..<cols {
                let key = RangeParser.address(region: .leftLabels, row: row, col: col)
                if let value = table.cellValues[key], value != .empty {
                    return true
                }
            }
        }
        return false
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

    private func chart(withId id: String) -> ChartModel? {
        for sheet in project.sheets {
            if let chart = sheet.charts.first(where: { $0.id == id }) {
                return chart
            }
        }
        return nil
    }

    private func sheetId(containingTableId tableId: String) -> String? {
        for sheet in project.sheets {
            if sheet.tables.contains(where: { $0.id == tableId }) {
                return sheet.id
            }
        }
        return nil
    }

    private func estimateSummaryRowCount(sourceTable: TableModel,
                                         groupBy: [Int],
                                         sourceRange: String?) -> Int {
        guard !groupBy.isEmpty else {
            return CanvasGridSizing.minBodyRows
        }
        let rowBounds = summaryRowBounds(table: sourceTable, sourceRange: sourceRange)
        var seen = Set<SummaryKey>()
        for row in rowBounds.start...rowBounds.end {
            let values = groupBy.map { col -> CellValue in
                let key = RangeParser.address(region: .body, row: row, col: col)
                return sourceTable.cellValues[key] ?? .empty
            }
            if values.allSatisfy({ $0 == .empty }) {
                continue
            }
            seen.insert(SummaryKey(values: values))
        }
        return max(CanvasGridSizing.minBodyRows, seen.count)
    }

    private func summaryRowBounds(table: TableModel,
                                  sourceRange: String?) -> (start: Int, end: Int) {
        let maxRow = max(0, table.gridSpec.bodyRows - 1)
        guard let sourceRange,
              let parsed = try? RangeParser.parse(sourceRange),
              parsed.region == .body else {
            return (0, maxRow)
        }
        let rowStart = max(0, min(parsed.start.row, parsed.end.row))
        let rowEnd = min(maxRow, max(parsed.start.row, parsed.end.row))
        if rowStart > rowEnd {
            return (0, maxRow)
        }
        return (rowStart, rowEnd)
    }

    private func isReadOnlyTable(tableId: String) -> Bool {
        table(withId: tableId)?.summarySpec != nil
    }

    private func columnTypeForBody(table: TableModel, col: Int) -> ColumnDataType {
        if table.bodyColumnTypes.indices.contains(col) {
            return table.bodyColumnTypes[col]
        }
        return .number
    }

    private func displayValue(for selection: CellSelection, table: TableModel) -> String {
        let key = RangeParser.address(region: selection.region, row: selection.row, col: selection.col)
        if let value = table.cellValues[key], value != .empty {
            if selection.region == .body {
                let columnType = columnTypeForBody(table: table, col: selection.col)
                return CellValue.displayString(value, columnType: columnType)
            }
            return value.displayString
        }
        if let formula = table.formulas[key]?.formula,
           !formula.isEmpty {
            return formula
        }
        return ""
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

    func selectedChart() -> ChartModel? {
        guard let selectedChartId else {
            return nil
        }
        return chart(withId: selectedChartId)
    }

    func setBodyColumnType(tableId: String, col: Int, type: ColumnDataType) {
        guard col >= 0 else {
            return
        }
        guard !isReadOnlyTable(tableId: tableId) else {
            return
        }
        apply(SetColumnTypeCommand(tableId: tableId, col: col, columnType: type), kind: .general)
    }

    private func clearSelectionIfInvalid(tableId: String) {
        guard let table = table(withId: tableId) else {
            return
        }
        if let selection = selectedCell,
           selection.tableId == tableId,
           !isSelectionValid(selection, for: table) {
            selectedCell = nil
        }
        if !selectedRanges.isEmpty {
            selectedRanges = selectedRanges.filter { range in
                guard range.tableId == tableId else {
                    return true
                }
                return isRangeValid(range, for: table)
            }
            if let range = activeRange(for: tableId),
               (selectedCell == nil || !(range.contains(selectedCell!))) {
                selectedCell = range.endCell
            }
        }
        if selectedRanges.isEmpty, selectedCell == nil {
            selectionAnchor = nil
        }
    }

    private func isSelectionValid(_ selection: CellSelection, for table: TableModel) -> Bool {
        let dims = regionDimensions(for: table, region: selection.region)
        return selection.row >= 0
            && selection.row < dims.rows
            && selection.col >= 0
            && selection.col < dims.cols
    }

    private func isRangeValid(_ range: TableRangeSelection, for table: TableModel) -> Bool {
        let dims = regionDimensions(for: table, region: range.region)
        let norm = range.normalized
        return norm.startRow >= 0
            && norm.endRow < dims.rows
            && norm.startCol >= 0
            && norm.endCol < dims.cols
    }

    private func regionDimensions(for table: TableModel, region: GridRegion) -> (rows: Int, cols: Int) {
        let grid = table.gridSpec
        let bands = grid.labelBands
        switch region {
        case .body:
            return (max(0, grid.bodyRows), max(0, grid.bodyCols))
        case .topLabels:
            return (max(0, bands.topRows), max(0, grid.bodyCols))
        case .bottomLabels:
            return (max(0, bands.bottomRows), max(0, grid.bodyCols))
        case .leftLabels:
            return (max(0, grid.bodyRows), max(0, bands.leftCols))
        case .rightLabels:
            return (max(0, grid.bodyRows), max(0, bands.rightCols))
        }
    }

    private func rangeIntersects(range: TableRangeSelection, address: RangeAddress) -> Bool {
        guard range.region == address.region else {
            return false
        }
        let norm = range.normalized
        let rowStart = min(address.start.row, address.end.row)
        let rowEnd = max(address.start.row, address.end.row)
        let colStart = min(address.start.col, address.end.col)
        let colEnd = max(address.start.col, address.end.col)
        let rowsOverlap = norm.startRow <= rowEnd && norm.endRow >= rowStart
        let colsOverlap = norm.startCol <= colEnd && norm.endCol >= colStart
        return rowsOverlap && colsOverlap
    }

    private func clampedCell(from selection: CellSelection,
                             deltaRow: Int,
                             deltaCol: Int,
                             table: TableModel) -> CellSelection {
        let dims = regionDimensions(for: table, region: selection.region)
        let maxRow = max(0, dims.rows - 1)
        let maxCol = max(0, dims.cols - 1)
        let row = min(max(selection.row + deltaRow, 0), maxRow)
        let col = min(max(selection.col + deltaCol, 0), maxCol)
        return CellSelection(tableId: selection.tableId,
                             region: selection.region,
                             row: row,
                             col: col)
    }

    private func moveSelection(deltaRow: Int,
                               deltaCol: Int,
                               extend: Bool,
                               addRange: Bool) {
        guard let current = selectedCell ?? activeSelectionRange()?.endCell,
              let table = table(withId: current.tableId) else {
            return
        }
        let target = clampedCell(from: current, deltaRow: deltaRow, deltaCol: deltaCol, table: table)
        if extend {
            if selectionAnchor == nil {
                selectionAnchor = current
            }
            extendSelection(to: target, addRange: addRange)
            return
        }
        if let activeRange = activeSelectionRange(),
           activeRange.tableId == current.tableId,
           activeRange.contains(target),
           !activeRange.isSingleCell {
            selectedCell = target
            selectionAnchor = target
            requestCanvasKeyFocus()
            return
        }
        replaceSelection(with: TableRangeSelection(cell: target),
                         activeCell: target,
                         anchor: target)
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
        if assignmentAlias(from: line, call: "proj.add_table(") != nil
            || assignmentAlias(from: line, call: "proj.add_summary_table(") != nil {
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
        guard line.contains("proj.add_table(") || line.contains("proj.add_summary_table(") else {
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
        if let alias = assignmentAlias(from: line, call: "proj.add_summary_table(") {
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

private struct SummaryKey: Hashable {
    let values: [CellValue]

    func hash(into hasher: inout Hasher) {
        for value in values {
            hasher.combine(value)
        }
    }
}
