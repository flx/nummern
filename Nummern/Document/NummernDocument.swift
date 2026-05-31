import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let nummern = UTType(exportedAs: "com.digitalhandstand.nummern.document")
}

/// The document *and* the focused store. Owns the command log (canonical),
/// the latest engine snapshot (display), selection/UI state, and the actions
/// that record commands and re-run the script. Kept deliberately small — recording
/// a command is one append; recomputation is one engine run.
final class NummernDocument: ReferenceFileDocument {
    typealias Snapshot = String   // the script text we persist

    static var readableContentTypes: [UTType] { [.nummern] }

    // Canonical + display state
    private(set) var log: CommandLog
    @Published private(set) var project: ProjectSnapshot = .empty
    @Published var selectedSheetId: String?
    @Published var selection: Selection = .none
    @Published var lastError: String?
    @Published private(set) var isRunning = false
    /// The script shown/edited in the code panel. Kept in sync with `log` after
    /// each recorded command; the user may also edit it freely and Run.
    @Published var scriptText: String = ""
    /// Latest run's stdout+stderr for the console.
    @Published private(set) var consoleText: String = ""

    private var counters: [String: Int] = ["sheet": 0, "table": 0, "chart": 0]
    private let runner: PythonRunner?
    private var runGeneration = 0
    /// The environment UndoManager (set by the view). Registering undo here also
    /// marks the document dirty so SwiftUI knows to save.
    weak var undoManager: UndoManager?

    // MARK: recording with undo

    /// Append a command, register its inverse for undo, and re-run.
    private func record(_ command: Command, name: String) {
        record([command], name: name)
    }

    /// Append several commands as a single undo step.
    private func record(_ commands: [Command], name: String) {
        let previous = log.commands
        commands.forEach { log.append($0) }
        registerUndo(restoring: previous, name: name)
        scheduleRun()
    }

    private func registerUndo(restoring commands: [Command], name: String) {
        undoManager?.registerUndo(withTarget: self) { document in
            document.restore(commands, name: name)
        }
        undoManager?.setActionName(name)
    }

    /// Swap the command list to a prior/next state. Registers the opposite move,
    /// so this drives both undo and redo.
    func restore(_ commands: [Command], name: String) {
        let current = log.commands
        log.replaceAll(commands)
        selection = .none
        registerUndo(restoring: current, name: name)
        scheduleRun()
    }

    // MARK: lifecycle

    /// New, empty document with one starter sheet.
    init() {
        self.log = CommandLog()
        self.runner = try? PythonRunner()
        addSheet(name: "Sheet 1")
        scriptText = log.script()
    }

    init(configuration: ReadConfiguration) throws {
        let wrapper = configuration.file
        let loadedScript = wrapper.fileWrappers?["script.py"]?.regularFileContents
            .flatMap { String(data: $0, encoding: .utf8) }
        self.log = CommandLog.parse(loadedScript ?? CommandLog().script())
        self.runner = try? PythonRunner()
        seedCounters(fromScript: loadedScript ?? "")
        scriptText = log.script()
        // Snapshot fast-open: show the cached project.json immediately, then
        // re-run the script to reconcile (the script stays the source of truth).
        if let jsonData = wrapper.fileWrappers?["project.json"]?.regularFileContents,
           let snapshot = try? JSONDecoder().decode(ProjectSnapshot.self, from: jsonData) {
            project = snapshot
            selectedSheetId = snapshot.sheets.first?.id
        }
        runNow()
    }

    func snapshot(contentType: UTType) throws -> Snapshot { log.script() }

    func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        var children: [String: FileWrapper] = [:]
        children["script.py"] = FileWrapper(regularFileWithContents: Data(snapshot.utf8))
        if let json = try? JSONEncoder().encode(project) {
            children["project.json"] = FileWrapper(regularFileWithContents: json)
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }

    // MARK: id generation

    private func nextId(_ kind: String) -> String {
        counters[kind, default: 0] += 1
        return "\(kind)_\(counters[kind]!)"
    }

    private func seedCounters(fromScript script: String) {
        for kind in counters.keys {
            var maxN = 0
            let pattern = "\(kind)_"
            for token in script.components(separatedBy: CharacterSet(charactersIn: " \t\n\"'(),=[]")) {
                if token.hasPrefix(pattern), let n = Int(token.dropFirst(pattern.count)) {
                    maxN = max(maxN, n)
                }
            }
            counters[kind] = maxN
        }
    }

    // MARK: actions (record a command, then re-run)

    @discardableResult
    func addSheet(name: String) -> String {
        let id = nextId("sheet")
        if selectedSheetId == nil { selectedSheetId = id }
        record(AddSheetCommand(id: id, name: name), name: "Add Sheet")
        return id
    }

    @discardableResult
    func addTable(rows: Int = 6, cols: Int = 4, labels: LabelBandsDTO = .init(top: 1, left: 0, bottom: 0, right: 0)) -> String? {
        guard let sheetId = selectedSheetId ?? project.sheets.first?.id else { return nil }
        let id = nextId("table")
        let origin = nextTableOrigin()
        selection = .table(id)
        record(AddTableCommand(sheetId: sheetId, id: id, x: origin.x, y: origin.y,
                               rows: rows, cols: cols, labels: labels), name: "Add Table")
        return id
    }

    func moveTable(_ id: String, to point: CGPoint) {
        record(SetPositionCommand(tableId: id, x: Double(point.x), y: Double(point.y)), name: "Move Table")
    }

    func resizeTable(_ id: String, rows: Int, cols: Int) {
        record(ResizeCommand(tableId: id, rows: rows, cols: cols), name: "Resize Table")
    }

    func setLiteral(_ id: String, range: String, values: [[CellValue]]) {
        record(SetLiteralCommand(tableId: id, range: range, values: values), name: "Edit Cells")
    }

    func setExpr(_ id: String, target: String, expr: String) {
        record(SetExprCommand(tableId: id, target: target, expr: expr), name: "Set Formula")
    }

    func setLabelBand(_ id: String, region: String, values: [String]) {
        record(SetLabelBandCommand(tableId: id, region: region, values: values), name: "Edit Labels")
    }

    // MARK: charts & summaries

    /// The table implied by the current selection (a table or a cell in one).
    var currentTableId: String? {
        switch selection {
        case .table(let id): return id
        case .cell(let id, _, _): return id
        default: return nil
        }
    }

    private func sheetId(ofTable tableId: String) -> String? {
        project.sheets.first { $0.tables.contains { $0.id == tableId } }?.id
    }

    var selectedChartId: String? {
        if case .chart(let id) = selection { return id }
        return nil
    }

    func chart(id: String) -> ChartSnapshot? {
        for sheet in project.sheets { if let c = sheet.charts.first(where: { $0.id == id }) { return c } }
        return nil
    }

    @discardableResult
    func addChart(chartType: String) -> String? {
        guard let tableId = currentTableId, let table = project.table(id: tableId),
              let sheet = sheetId(ofTable: tableId) else {
            lastError = "Select a table to chart."
            return nil
        }
        let ranges = SelectionDerivation.chartRanges(SelectionDerivation.bodyRect(table))
        let id = nextId("chart")
        selection = .chart(id)
        record(AddChartCommand(sheetId: sheet, id: id, chartType: chartType, tableId: tableId,
                               valueRange: ranges.value, labelRange: ranges.label, title: ""),
               name: "Add Chart")
        return id
    }

    @discardableResult
    func addSummary() -> String? {
        guard let tableId = currentTableId, let table = project.table(id: tableId),
              let sheet = sheetId(ofTable: tableId) else {
            lastError = "Select a table to summarize."
            return nil
        }
        let spec = SelectionDerivation.summarySpec(SelectionDerivation.bodyRect(table),
                                                   table: table, scoped: false)
        guard !spec.values.isEmpty else {
            lastError = "No numeric columns to summarize."
            return nil
        }
        let id = nextId("table")
        selection = .table(id)
        record(AddSummaryCommand(sheetId: sheet, id: id, sourceId: tableId,
                                 groupBy: spec.groupBy, values: spec.values), name: "Add Summary")
        return id
    }

    func setChartSpec(_ chartId: String, chartType: String? = nil, title: String? = nil,
                      showLegend: Bool? = nil, valueRange: String? = nil, labelRange: String? = nil) {
        record(SetChartSpecCommand(chartId: chartId, chartType: chartType, title: title,
                                   showLegend: showLegend, valueRange: valueRange,
                                   labelRange: labelRange), name: "Edit Chart")
    }

    func moveChart(_ chartId: String, to point: CGPoint) {
        record(SetChartPositionCommand(chartId: chartId, x: Double(point.x), y: Double(point.y)),
               name: "Move Chart")
    }

    func previewChartRect(chartId: String, x: Double, y: Double) {
        for s in project.sheets.indices {
            if let c = project.sheets[s].charts.firstIndex(where: { $0.id == chartId }) {
                project.sheets[s].charts[c].rect.x = x
                project.sheets[s].charts[c].rect.y = y
                return
            }
        }
    }

    // MARK: cell selection & editing

    var selectedCell: (tableId: String, row: Int, col: Int)? {
        if case .cell(let id, let r, let c) = selection { return (id, r, c) }
        return nil
    }

    func selectCell(tableId: String, row: Int, col: Int) {
        selection = .cell(tableId: tableId, row: row, col: col)
    }

    /// Text to show in the formula bar for the selected cell: the recorded
    /// expression if it's formula-defined (provenance), else the literal value.
    func selectedCellText() -> String {
        guard let sel = selectedCell else { return "" }
        let ref = CellAddress.cellRef(row: sel.row, col: sel.col)
        if let expr = FormulaProvenance.expression(for: sel.tableId, ref: ref, in: log.commands) {
            return "=\(expr)"
        }
        guard let table = project.table(id: sel.tableId) else { return "" }
        return table.cell(row: sel.row, col: sel.col).displayText()
    }

    /// Commit formula-bar / cell-editor text to the selected cell.
    func commitCellInput(_ text: String) {
        guard let sel = selectedCell else { return }
        let ref = CellAddress.cellRef(row: sel.row, col: sel.col)
        switch CellInput.parse(text) {
        case .literal(let value):
            setLiteral(sel.tableId, range: ref, values: [[value]])
        case .formula(let expr):
            setExpr(sel.tableId, target: ref, expr: expr)
        }
    }

    // MARK: keyboard navigation (README §5.10.8)

    func moveSelection(_ key: KeyboardNavigator.Key) {
        guard let sel = selectedCell, let table = project.table(id: sel.tableId) else { return }
        let next = KeyboardNavigator.move(from: (sel.row, sel.col), key: key,
                                          rows: table.grid.rows, cols: table.grid.cols)
        selection = .cell(tableId: sel.tableId, row: next.row, col: next.col)
    }

    func clearSelection() { selection = .none }

    func clearSelectedCell() {
        guard let sel = selectedCell else { return }
        let ref = CellAddress.cellRef(row: sel.row, col: sel.col)
        record(ClearRangeCommand(tableId: sel.tableId, range: ref), name: "Clear Cell")
    }

    // MARK: CSV import / export (README §5.7)

    /// Import CSV/TSV text as a new label-free table. The engine infers per-column
    /// dtypes from the values.
    func importCSV(text: String) {
        let block = ClipboardParser.parse(text)
        guard !block.isEmpty, let sheetId = selectedSheetId ?? project.sheets.first?.id else { return }
        let cols = block.map(\.count).max() ?? 0
        guard cols > 0 else { return }
        let id = nextId("table")
        let origin = nextTableOrigin()
        let range = "A0:\(CellAddress.cellRef(row: block.count - 1, col: cols - 1))"
        selection = .table(id)
        record([
            AddTableCommand(sheetId: sheetId, id: id, x: origin.x, y: origin.y,
                            rows: block.count, cols: cols,
                            labels: .init(top: 0, left: 0, bottom: 0, right: 0)),
            SetLiteralCommand(tableId: id, range: range, values: block),
        ], name: "Import CSV")
    }

    /// CSV for a table's body (trimmed to its content bounds).
    func exportCSV(tableId: String) -> String? {
        guard let table = project.table(id: tableId) else { return nil }
        return CSVCodec.encode(CSVCodec.bodyBlock(table))
    }

    /// Local immediate rect update during a drag (no command recorded yet).
    func previewRect(tableId: String, x: Double, y: Double) {
        mutateTable(tableId) { $0.rect.x = x; $0.rect.y = y }
    }

    private func mutateTable(_ id: String, _ body: (inout TableSnapshot) -> Void) {
        for s in project.sheets.indices {
            if let t = project.sheets[s].tables.firstIndex(where: { $0.id == id }) {
                body(&project.sheets[s].tables[t])
                return
            }
        }
    }

    private func nextTableOrigin() -> CGPoint {
        let count = project.sheets.reduce(0) { $0 + $1.tables.count + $1.charts.count }
        let offset = Double(count) * 24.0
        return CGPoint(x: 80 + offset, y: 80 + offset)
    }

    // MARK: running the engine

    /// Record-driven run: refresh the editor text from the canonical log and run.
    func scheduleRun() {
        scriptText = log.script()
        performRun(scriptText)
    }

    /// Run All: run exactly what the user sees, and re-parse the generated region
    /// back into the command log so subsequent UI edits append to it (README §6.4).
    func runAll() {
        log = CommandLog.parse(scriptText)
        seedCounters(fromScript: scriptText)
        performRun(scriptText)
    }

    /// Reset Runtime: a fresh run of the canonical script (every run is already a
    /// new Python process).
    func resetRuntime() {
        scriptText = log.script()
        performRun(scriptText)
    }

    /// Run a selected fragment with imports + an injected project if needed.
    func runSelection(_ selection: String) {
        guard !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let composed = ScriptComposer.selectionScript(header: log.userCode, selection: selection)
        performRun(composed)
    }

    private func performRun(_ script: String) {
        guard let runner else {
            lastError = "Python engine unavailable."
            return
        }
        runGeneration += 1
        let generation = runGeneration
        isRunning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var snapshot: ProjectSnapshot?
            var stdout = "", stderr = "", failure: String?
            do {
                let result = try runner.run(script: script, emit: .json)
                snapshot = result.snapshot; stdout = result.stdout; stderr = result.stderr
            } catch let error as PythonRunError {
                stderr = error.stderrText ?? ""
                failure = error.errorDescription ?? "Run failed."
            } catch {
                failure = error.localizedDescription
            }
            DispatchQueue.main.async {
                self?.applyRun(generation, snapshot: snapshot, stdout: stdout,
                               stderr: stderr, failure: failure)
            }
        }
    }

    private func applyRun(_ generation: Int, snapshot: ProjectSnapshot?,
                          stdout: String, stderr: String, failure: String?) {
        guard generation == runGeneration else { return }   // discard stale run
        isRunning = false
        consoleText = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        if failure != nil {
            let parsed = PythonErrorParser.parse(stderr)
            lastError = stderr.isEmpty ? failure : parsed.displayString()
            return
        }
        lastError = nil
        if let snapshot {
            project = snapshot
            if selectedSheetId == nil { selectedSheetId = project.sheets.first?.id }
        }
    }

    /// Synchronous run used on open (keeps initial render correct).
    private func runNow() {
        guard let runner else { return }
        if let result = try? runner.run(script: log.script(), emit: .json) {
            project = result.snapshot
            if selectedSheetId == nil { selectedSheetId = project.sheets.first?.id }
            consoleText = result.stdout
        }
    }

}

/// UI selection state (expanded in S4).
enum Selection: Equatable {
    case none
    case table(String)
    case chart(String)
    case cell(tableId: String, row: Int, col: Int)
}
