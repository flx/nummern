import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Binding var document: NummernDocument
    @Environment(\.undoManager) private var undoManager
    @StateObject private var viewModel: CanvasViewModel
    @State private var selectedSheetId: String?
    @State private var pythonRunError: String?
    @State private var isRunningScript = false
    @State private var isExporting = false
    @State private var isImportingCSV = false
    @State private var isExportingCSV = false
    @State private var isShowingSummaryBuilder = false
    @State private var summaryBuilderState = SummaryBuilderState(sourceTableId: "",
                                                                 sourceRange: nil,
                                                                 columns: [],
                                                                 groupBy: [],
                                                                 valueColumn: 0,
                                                                 aggregation: .sum)
    @State private var autoRunWorkItem: DispatchWorkItem?
    @State private var pendingAutoRun = false
    @State private var didAppear = false
    @State private var lastPrintedPythonLog: String = ""
    @State private var scriptSelection = NSRange(location: 0, length: 0)
    @State private var scriptRunRevision = ScriptRunRevision()
    private let autoRunDelay: TimeInterval = 0.4

    init(document: Binding<NummernDocument>) {
        _document = document
        _viewModel = StateObject(wrappedValue: CanvasViewModel(project: document.wrappedValue.project,
                                                               historyJSON: document.wrappedValue.historyJSON))
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                if viewModel.project.sheets.isEmpty {
                    VStack(spacing: 12) {
                        Text("No sheets yet")
                            .font(.headline)
                        Button("Add Sheet") {
                            addSheet()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TabView(selection: $selectedSheetId) {
                        ForEach(viewModel.project.sheets, id: \.id) { sheet in
                            CanvasView(sheet: sheet, viewModel: viewModel)
                                .tag(sheet.id)
                                .tabItem {
                                    Text(sheet.name)
                                }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                if let selectedTable = viewModel.selectedTable() {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected Table")
                            .font(.headline)
                        Text(selectedTable.id)
                            .font(.subheadline)
                        if let summarySpec = selectedTable.summarySpec {
                            Text("Summary of \(summarySpec.sourceTableId)")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        labelBandStepper(title: "Body Rows",
                                          value: bodyRowsBinding(table: selectedTable),
                                          range: 1...200)
                            .disabled(selectedTable.summarySpec != nil)
                        labelBandStepper(title: "Body Columns",
                                          value: bodyColsBinding(table: selectedTable),
                                          range: 1...200)
                            .disabled(selectedTable.summarySpec != nil)
                        labelBandStepper(title: "Top Labels",
                                          value: labelBandBinding(table: selectedTable, keyPath: \.topRows))
                            .disabled(selectedTable.summarySpec != nil)
                        labelBandStepper(title: "Left Labels",
                                          value: labelBandBinding(table: selectedTable, keyPath: \.leftCols))
                            .disabled(selectedTable.summarySpec != nil)
                        labelBandStepper(title: "Bottom Labels",
                                          value: labelBandBinding(table: selectedTable, keyPath: \.bottomRows))
                            .disabled(selectedTable.summarySpec != nil)
                        labelBandStepper(title: "Right Labels",
                                          value: labelBandBinding(table: selectedTable, keyPath: \.rightCols))
                            .disabled(selectedTable.summarySpec != nil)
                        if let selection = viewModel.selectedCell,
                           selection.tableId == selectedTable.id,
                           selection.region == .body {
                            let columnLabel = RangeParser.columnLabel(from: selection.col)
                            Picker("Column Type (\(columnLabel))",
                                   selection: columnTypeBinding(table: selectedTable, col: selection.col)) {
                                ForEach(ColumnDataType.allCases, id: \.self) { columnType in
                                    Text(columnType.displayName).tag(columnType)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(selectedTable.summarySpec != nil)
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(6)
                }

                if let selectedChart = viewModel.selectedChart() {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected Chart")
                            .font(.headline)
                        Text(selectedChart.id)
                            .font(.subheadline)
                        Picker("Chart Type", selection: chartTypeBinding(chart: selectedChart)) {
                            ForEach(ChartType.allCases, id: \.self) { chartType in
                                Text(chartType.displayName).tag(chartType)
                            }
                        }
                        .pickerStyle(.menu)
                        TextField("Value Range", text: chartValueRangeBinding(chart: selectedChart))
                        TextField("Label Range", text: chartLabelRangeBinding(chart: selectedChart))
                        TextField("Title", text: chartTitleBinding(chart: selectedChart))
                        TextField("X Axis Title", text: chartXAxisTitleBinding(chart: selectedChart))
                        TextField("Y Axis Title", text: chartYAxisTitleBinding(chart: selectedChart))
                        Toggle("Show Legend", isOn: chartShowLegendBinding(chart: selectedChart))
                    }
                    .padding(8)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(6)
                }

                Text("script.py")
                    .font(.headline)
                ScriptEditor(text: $document.script, selectedRange: $scriptSelection)
            }
            .frame(minWidth: 320)
            .padding(12)
        }
        .overlay {
            HStack {
                Button("Copy") {
                    viewModel.copySelectionToClipboard()
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    viewModel.pasteFromClipboard()
                }
                .keyboardShortcut("v", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .alert("Python Run Failed", isPresented: Binding(get: {
            pythonRunError != nil
        }, set: { newValue in
            if !newValue {
                pythonRunError = nil
            }
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pythonRunError ?? "Unknown error")
        }
        .sheet(isPresented: $isShowingSummaryBuilder) {
            SummaryBuilderView(state: $summaryBuilderState,
                               onCancel: { isShowingSummaryBuilder = false },
                               onCreate: { createSummaryTableFromBuilder() })
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    addSheet()
                } label: {
                    Label("Add Sheet", systemImage: "plus.rectangle.on.rectangle")
                }
                Button {
                    addTable()
                } label: {
                    Label("Add Table", systemImage: "tablecells")
                }
                Button {
                    addChart()
                } label: {
                    Label("Add Chart", systemImage: "chart.xyaxis.line")
                }
                .disabled(isRunningScript || viewModel.selectedTable() == nil)
                Button {
                    openSummaryBuilder()
                } label: {
                    Label("Create Summary", systemImage: "sum")
                }
                .disabled(isRunningScript
                          || viewModel.selectedTable() == nil
                          || viewModel.selectedTable()?.summarySpec != nil)
                Button {
                    importCSV()
                } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
                .disabled(isRunningScript || isImportingCSV)
                Button {
                    runScript()
                } label: {
                    Label("Run All", systemImage: "play.circle")
                }
                .disabled(isRunningScript)

                Button {
                    runSelection()
                } label: {
                    Label("Run Selection", systemImage: "play.fill")
                }
                .disabled(isRunningScript || scriptSelection.length == 0)

                Button {
                    resetRuntime()
                } label: {
                    Label("Reset Runtime", systemImage: "arrow.counterclockwise")
                }
                .disabled(isRunningScript)

                Button {
                    exportNumpyScript()
                } label: {
                    Label("Export NumPy", systemImage: "square.and.arrow.up")
                }
                .disabled(isRunningScript || isExporting)
                Button {
                    exportCSV()
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up.on.square")
                }
                .disabled(isRunningScript || isExportingCSV || viewModel.selectedTable() == nil)
            }
        }
        .onChange(of: viewModel.project) { _, newValue in
            document.project = newValue
        }
        .onChange(of: document.project) { _, newValue in
            if newValue != viewModel.project {
                viewModel.load(project: newValue, historyJSON: document.historyJSON)
                selectedSheetId = newValue.sheets.first?.id
            }
        }
        .onChange(of: viewModel.historyJSON) { _, newValue in
            document.historyJSON = newValue
        }
        .onChange(of: viewModel.pythonLog) { _, newValue in
            document.script = ScriptComposer.compose(existing: document.script,
                                                     generatedLog: newValue)
            logPythonChanges(newValue)
            if didAppear {
                scheduleAutoRun()
            }
        }
        .onChange(of: document.script) { _, _ in
            scriptRunRevision.bump()
        }
        .onAppear {
            if selectedSheetId == nil {
                selectedSheetId = viewModel.project.sheets.first?.id
            }
            viewModel.setUndoManager(undoManager)
            didAppear = true
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func addSheet() {
        let sheet = viewModel.addSheet()
        selectedSheetId = sheet.id
    }

    private func addTable() {
        guard let sheetId = selectedSheetId ?? viewModel.project.sheets.first?.id else {
            let sheet = viewModel.addSheet()
            selectedSheetId = sheet.id
            _ = viewModel.addTable(toSheetId: sheet.id)
            return
        }
        _ = viewModel.addTable(toSheetId: sheetId)
    }

    private func addChart() {
        guard let sheetId = selectedSheetId ?? viewModel.project.sheets.first?.id else {
            return
        }
        _ = viewModel.addChartForSelection(toSheetId: sheetId)
    }

    private func openSummaryBuilder() {
        guard let table = viewModel.selectedTable() else {
            return
        }
        var columns = Array(0..<table.gridSpec.bodyCols)
        var sourceRange: String? = nil
        if let range = viewModel.activeSelectionRange(),
           range.tableId == table.id,
           range.region == .body {
            let normalized = range.normalized
            if normalized.startCol <= normalized.endCol {
                columns = Array(normalized.startCol...normalized.endCol)
                sourceRange = normalized.rangeString()
            }
        }
        guard !columns.isEmpty else {
            return
        }
        let defaultGroup = Set([columns.first].compactMap { $0 })
        let valueColumn = columns.count > 1 ? columns[1] : columns[0]
        summaryBuilderState = SummaryBuilderState(sourceTableId: table.id,
                                                  sourceRange: sourceRange,
                                                  columns: columns,
                                                  groupBy: defaultGroup,
                                                  valueColumn: valueColumn,
                                                  aggregation: .sum)
        isShowingSummaryBuilder = true
    }

    private func createSummaryTableFromBuilder() {
        let groupBy = summaryBuilderState.groupBy.sorted()
        let valueSpec = SummaryValueSpec(column: summaryBuilderState.valueColumn,
                                         aggregation: summaryBuilderState.aggregation)
        if let table = viewModel.createSummaryTable(sourceTableId: summaryBuilderState.sourceTableId,
                                                    sourceRange: summaryBuilderState.sourceRange,
                                                    groupBy: groupBy,
                                                    values: [valueSpec]) {
            viewModel.selectTable(table.id)
        }
        isShowingSummaryBuilder = false
    }

    private func runScript() {
        let script = document.script
        let historyJSON = ScriptComposer.historyJSON(from: script) ?? document.historyJSON
        let runToken = scriptRunRevision.token()
        executeScript(script: script,
                      historyJSON: historyJSON,
                      updateHistory: true,
                      runToken: runToken)
    }

    private func runSelection() {
        guard let selectionScript = ScriptComposer.selectionScript(from: document.script,
                                                                   selectionRange: scriptSelection) else {
            return
        }
        let runToken = scriptRunRevision.token()
        executeScript(script: selectionScript,
                      historyJSON: document.historyJSON,
                      updateHistory: false,
                      runToken: runToken)
    }

    private func resetRuntime() {
        print("Resetting Python runtime (fresh run).")
        runScript()
    }

    private func executeScript(script: String,
                               historyJSON: String?,
                               updateHistory: Bool,
                               runToken: Int) {
        guard !isRunningScript else {
            return
        }
        isRunningScript = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let engine = try PythonEngineClient()
                let result = try engine.runProject(script: script)
                DispatchQueue.main.async {
                    guard scriptRunRevision.matches(runToken) else {
                        handleStaleRun()
                        return
                    }
                    viewModel.load(project: result.project, historyJSON: historyJSON)
                    if updateHistory {
                        document.historyJSON = historyJSON
                    }
                    isRunningScript = false
                    handlePendingAutoRun()
                }
            } catch {
                DispatchQueue.main.async {
                    guard scriptRunRevision.matches(runToken) else {
                        handleStaleRun()
                        return
                    }
                    pythonRunError = formatPythonError(error)
                    isRunningScript = false
                    handlePendingAutoRun()
                }
            }
        }
    }

    private func exportNumpyScript() {
        guard !isExporting else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "export_numpy.py"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            isExporting = true
            let script = document.script
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let engine = try PythonEngineClient()
                    let exportScript = try engine.exportNumpyScript(script: script, includeFormulas: true)
                    try exportScript.write(to: url, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        isExporting = false
                        print("Exported NumPy script to \(url.path)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        pythonRunError = error.localizedDescription
                        isExporting = false
                    }
                }
            }
        }
    }

    private func importCSV() {
        guard !isImportingCSV else {
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            isImportingCSV = true
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                guard let tableImport = CSVTableImporter.parse(text) else {
                    isImportingCSV = false
                    return
                }
                let sheetId = selectedSheetId ?? viewModel.project.sheets.first?.id ?? viewModel.addSheet().id
                let rows = max(CanvasGridSizing.minBodyRows, tableImport.values.count)
                let cols = max(CanvasGridSizing.minBodyCols, tableImport.columnTypes.count)
                if let table = viewModel.addTable(toSheetId: sheetId,
                                                  rows: rows,
                                                  cols: cols,
                                                  labels: .zero) {
                    for (index, columnType) in tableImport.columnTypes.enumerated() {
                        viewModel.setBodyColumnType(tableId: table.id, col: index, type: columnType)
                    }
                    viewModel.setRange(tableId: table.id,
                                       region: .body,
                                       startRow: 0,
                                       startCol: 0,
                                       values: tableImport.values)
                    viewModel.selectTable(table.id)
                }
                isImportingCSV = false
            } catch {
                pythonRunError = error.localizedDescription
                isImportingCSV = false
            }
        }
    }

    private func exportCSV() {
        guard !isExportingCSV,
              let table = viewModel.selectedTable() else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.nameFieldStringValue = "\(table.id).csv"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            isExportingCSV = true
            let csv = CSVTableExporter.export(table: table)
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                print("Exported CSV to \(url.path)")
            } catch {
                pythonRunError = error.localizedDescription
            }
            isExportingCSV = false
        }
    }

    private func scheduleAutoRun() {
        autoRunWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            triggerAutoRun()
        }
        autoRunWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autoRunDelay, execute: workItem)
    }

    private func triggerAutoRun() {
        if isRunningScript {
            pendingAutoRun = true
            return
        }
        runScript()
    }

    private func handlePendingAutoRun() {
        guard pendingAutoRun else {
            return
        }
        pendingAutoRun = false
        scheduleAutoRun()
    }

    private func handleStaleRun() {
        isRunningScript = false
        pendingAutoRun = true
        handlePendingAutoRun()
    }

    private func labelBandBinding(table: TableModel,
                                  keyPath: WritableKeyPath<LabelBands, Int>) -> Binding<Int> {
        Binding(
            get: { table.gridSpec.labelBands[keyPath: keyPath] },
            set: { newValue in
                var bands = table.gridSpec.labelBands
                bands[keyPath: keyPath] = max(0, newValue)
                viewModel.setLabelBands(tableId: table.id, labelBands: bands)
            }
        )
    }

    private func columnTypeBinding(table: TableModel, col: Int) -> Binding<ColumnDataType> {
        Binding(
            get: {
                if table.bodyColumnTypes.indices.contains(col) {
                    return table.bodyColumnTypes[col]
                }
                return .number
            },
            set: { newValue in
                viewModel.setBodyColumnType(tableId: table.id, col: col, type: newValue)
            }
        )
    }

    @ViewBuilder
    private func labelBandStepper(title: String,
                                  value: Binding<Int>,
                                  range: ClosedRange<Int> = 0...10) -> some View {
        Stepper("\(title): \(value.wrappedValue)", value: value, in: range)
    }

    private func bodyRowsBinding(table: TableModel) -> Binding<Int> {
        Binding(
            get: { table.gridSpec.bodyRows },
            set: { newValue in
                viewModel.setBodyRows(tableId: table.id,
                                      rows: max(CanvasGridSizing.minBodyRows, newValue))
            }
        )
    }

    private func bodyColsBinding(table: TableModel) -> Binding<Int> {
        Binding(
            get: { table.gridSpec.bodyCols },
            set: { newValue in
                viewModel.setBodyCols(tableId: table.id,
                                      cols: max(CanvasGridSizing.minBodyCols, newValue))
            }
        )
    }

    private func chartTypeBinding(chart: ChartModel) -> Binding<ChartType> {
        Binding(
            get: { chart.chartType },
            set: { newValue in
                viewModel.setChartType(chartId: chart.id, chartType: newValue)
            }
        )
    }

    private func chartValueRangeBinding(chart: ChartModel) -> Binding<String> {
        Binding(
            get: { chart.valueRange },
            set: { newValue in
                viewModel.setChartValueRange(chartId: chart.id, valueRange: newValue)
            }
        )
    }

    private func chartLabelRangeBinding(chart: ChartModel) -> Binding<String> {
        Binding(
            get: { chart.labelRange ?? "" },
            set: { newValue in
                viewModel.setChartLabelRange(chartId: chart.id,
                                             labelRange: newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newValue)
            }
        )
    }

    private func chartTitleBinding(chart: ChartModel) -> Binding<String> {
        Binding(
            get: { chart.title },
            set: { newValue in
                viewModel.setChartTitle(chartId: chart.id, title: newValue)
            }
        )
    }

    private func chartXAxisTitleBinding(chart: ChartModel) -> Binding<String> {
        Binding(
            get: { chart.xAxisTitle },
            set: { newValue in
                viewModel.setChartXAxisTitle(chartId: chart.id, title: newValue)
            }
        )
    }

    private func chartYAxisTitleBinding(chart: ChartModel) -> Binding<String> {
        Binding(
            get: { chart.yAxisTitle },
            set: { newValue in
                viewModel.setChartYAxisTitle(chartId: chart.id, title: newValue)
            }
        )
    }

    private func chartShowLegendBinding(chart: ChartModel) -> Binding<Bool> {
        Binding(
            get: { chart.showLegend },
            set: { newValue in
                viewModel.setChartShowLegend(chartId: chart.id, showLegend: newValue)
            }
        )
    }

    private func logPythonChanges(_ newValue: String) {
        guard !newValue.isEmpty else {
            lastPrintedPythonLog = ""
            return
        }

        let output: String
        if newValue.hasPrefix(lastPrintedPythonLog) {
            let start = newValue.index(newValue.startIndex, offsetBy: lastPrintedPythonLog.count)
            let delta = String(newValue[start...]).trimmingCharacters(in: .newlines)
            if delta.isEmpty {
                return
            }
            output = delta
        } else {
            output = newValue
        }

        lastPrintedPythonLog = newValue
        print("Event Log:\n\(output)")
    }

    private func formatPythonError(_ error: Error) -> String {
        if let engineError = error as? PythonEngineError {
            switch engineError {
            case .pythonFailed(_, let stderr):
                let detail = PythonErrorParser.parse(stderr: stderr)
                print("Python stderr:\n\(stderr)")
                if let line = detail.line {
                    return "Line \(line): \(detail.message)"
                }
                return detail.message
            default:
                print("Python error: \(engineError.localizedDescription)")
                return engineError.localizedDescription
            }
        }
        print("Python error: \(error.localizedDescription)")
        return error.localizedDescription
    }
}

struct ScriptEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var isEditable: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindPanel = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.string = text
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable
        let clamped = clampRange(selectedRange, for: text)
        if textView.selectedRange() != clamped {
            textView.setSelectedRange(clamped)
        }
    }

    private func clampRange(_ range: NSRange, for text: String) -> NSRange {
        let length = text.utf16.count
        let location = min(range.location, length)
        let maxLength = max(0, length - location)
        let clampedLength = min(range.length, maxLength)
        return NSRange(location: location, length: clampedLength)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: ScriptEditor
        weak var textView: NSTextView?

        init(_ parent: ScriptEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else {
                return
            }
            let newText = textView.string
            if parent.text != newText {
                parent.text = newText
            }
            let clamped = parent.clampRange(textView.selectedRange(), for: newText)
            if parent.selectedRange != clamped {
                parent.selectedRange = clamped
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else {
                return
            }
            let clamped = parent.clampRange(textView.selectedRange(), for: textView.string)
            if parent.selectedRange != clamped {
                parent.selectedRange = clamped
            }
        }
    }
}

struct SummaryBuilderState: Equatable {
    var sourceTableId: String
    var sourceRange: String?
    var columns: [Int]
    var groupBy: Set<Int>
    var valueColumn: Int
    var aggregation: SummaryAggregation
}

struct SummaryBuilderView: View {
    @Binding var state: SummaryBuilderState
    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Summary Table")
                .font(.headline)

            Text("Source: \(state.sourceTableId)")
                .font(.subheadline)

            if state.columns.isEmpty {
                Text("No body columns available.")
                    .foregroundColor(.secondary)
            } else {
                Form {
                    Section("Group By Columns") {
                        ForEach(state.columns, id: \.self) { column in
                            Toggle("Column \(RangeParser.columnLabel(from: column))",
                                   isOn: groupByBinding(column))
                        }
                    }

                    Section("Value") {
                        Picker("Column", selection: $state.valueColumn) {
                            ForEach(state.columns, id: \.self) { column in
                                Text("Column \(RangeParser.columnLabel(from: column))").tag(column)
                            }
                        }
                        Picker("Aggregation", selection: $state.aggregation) {
                            ForEach(SummaryAggregation.allCases, id: \.self) { aggregation in
                                Text(aggregation.displayName).tag(aggregation)
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Create") {
                    onCreate()
                }
                .disabled(state.columns.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 320)
    }

    private func groupByBinding(_ column: Int) -> Binding<Bool> {
        Binding(
            get: { state.groupBy.contains(column) },
            set: { isOn in
                if isOn {
                    state.groupBy.insert(column)
                } else {
                    state.groupBy.remove(column)
                }
            }
        )
    }
}

struct PythonErrorDetail: Equatable {
    let line: Int?
    let message: String
}

enum PythonErrorParser {
    static func parse(stderr: String) -> PythonErrorDetail {
        let lines = stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let message = extractMessage(from: lines) ?? "Python run failed."
        let lineNumber = extractLineNumber(from: stderr)
        return PythonErrorDetail(line: lineNumber, message: message)
    }

    private static func extractMessage(from lines: [String]) -> String? {
        guard let last = lines.last else {
            return nil
        }
        if last.hasPrefix("Error:") {
            return last.replacingOccurrences(of: "Error:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return last
    }

    private static func extractLineNumber(from stderr: String) -> Int? {
        let pattern = #"File \"[^\"]+\", line ([0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let matches = regex.matches(in: stderr, options: [], range: NSRange(stderr.startIndex..., in: stderr))
        guard let match = matches.last, match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: stderr) else {
            return nil
        }
        return Int(stderr[range])
    }
}

struct ScriptRunRevision: Equatable {
    private(set) var value: Int = 0

    mutating func bump() {
        value &+= 1
    }

    func token() -> Int {
        value
    }

    func matches(_ token: Int) -> Bool {
        token == value
    }
}
