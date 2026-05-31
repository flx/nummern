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
    let log: CommandLog
    @Published private(set) var project: ProjectSnapshot = .empty
    @Published var selectedSheetId: String?
    @Published var selection: Selection = .none
    @Published var lastError: String?
    @Published private(set) var isRunning = false

    private var counters: [String: Int] = ["sheet": 0, "table": 0, "chart": 0]
    private let runner: PythonRunner?
    private var runGeneration = 0

    // MARK: lifecycle

    /// New, empty document with one starter sheet.
    init() {
        self.log = CommandLog()
        self.runner = try? PythonRunner()
        addSheet(name: "Sheet 1")
    }

    init(configuration: ReadConfiguration) throws {
        let wrapper = configuration.file
        let scriptData = wrapper.fileWrappers?["script.py"]?.regularFileContents
        let scriptText = scriptData.flatMap { String(data: $0, encoding: .utf8) }
        self.log = CommandLog.parse(scriptText ?? CommandLog().script())
        self.runner = try? PythonRunner()
        seedCounters(fromScript: scriptText ?? "")
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
        log.append(AddSheetCommand(id: id, name: name))
        if selectedSheetId == nil { selectedSheetId = id }
        scheduleRun()
        return id
    }

    @discardableResult
    func addTable(rows: Int = 6, cols: Int = 4, labels: LabelBandsDTO = .init(top: 1, left: 0, bottom: 0, right: 0)) -> String? {
        guard let sheetId = selectedSheetId ?? project.sheets.first?.id else { return nil }
        let id = nextId("table")
        let origin = nextTableOrigin()
        log.append(AddTableCommand(sheetId: sheetId, id: id, x: origin.x, y: origin.y,
                                   rows: rows, cols: cols, labels: labels))
        selection = .table(id)
        scheduleRun()
        return id
    }

    func moveTable(_ id: String, to point: CGPoint) {
        log.append(SetPositionCommand(tableId: id, x: Double(point.x), y: Double(point.y)))
        scheduleRun()
    }

    func resizeTable(_ id: String, rows: Int, cols: Int) {
        log.append(ResizeCommand(tableId: id, rows: rows, cols: cols))
        scheduleRun()
    }

    func setLiteral(_ id: String, range: String, values: [[CellValue]]) {
        log.append(SetLiteralCommand(tableId: id, range: range, values: values))
        scheduleRun()
    }

    func setExpr(_ id: String, target: String, expr: String) {
        log.append(SetExprCommand(tableId: id, target: target, expr: expr))
        scheduleRun()
    }

    func setLabelBand(_ id: String, region: String, values: [String]) {
        log.append(SetLabelBandCommand(tableId: id, region: region, values: values))
        scheduleRun()
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

    func scheduleRun() {
        // Debounced re-run (S5 will add edit-coalescing); for now run on a hop.
        runGeneration += 1
        let generation = runGeneration
        let script = log.script()
        guard let runner else {
            lastError = "Python engine unavailable."
            return
        }
        isRunning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome: Result<PythonRunner.RunResult, Error>
            do { outcome = .success(try runner.run(script: script, emit: .json)) }
            catch { outcome = .failure(error) }
            DispatchQueue.main.async { self?.applyOutcome(outcome, generation: generation) }
        }
    }

    private func applyOutcome(_ outcome: Result<PythonRunner.RunResult, Error>, generation: Int) {
        guard generation == runGeneration else { return }   // discard stale run
        isRunning = false
        switch outcome {
        case .failure(let error):
            lastError = error.localizedDescription
        case .success(let result):
            lastError = nil
            project = result.snapshot
            if selectedSheetId == nil { selectedSheetId = project.sheets.first?.id }
        }
    }

    /// Synchronous run used on open (keeps initial render correct).
    private func runNow() {
        guard let runner else { return }
        if let result = try? runner.run(script: log.script(), emit: .json) {
            project = result.snapshot
            if selectedSheetId == nil { selectedSheetId = project.sheets.first?.id }
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
