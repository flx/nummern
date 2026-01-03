import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Binding var document: NummernDocument
    @StateObject private var viewModel: CanvasViewModel
    @State private var selectedSheetId: String?
    @State private var pythonRunError: String?
    @State private var isRunningScript = false
    @State private var isExporting = false
    @State private var autoRunWorkItem: DispatchWorkItem?
    @State private var pendingAutoRun = false
    @State private var didAppear = false
    @State private var lastPrintedPythonLog: String = ""
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
                        labelBandStepper(title: "Body Rows",
                                          value: bodyRowsBinding(table: selectedTable),
                                          range: 1...200)
                        labelBandStepper(title: "Body Columns",
                                          value: bodyColsBinding(table: selectedTable),
                                          range: 1...200)
                        labelBandStepper(title: "Top Labels",
                                          value: labelBandBinding(table: selectedTable, keyPath: \.topRows))
                        labelBandStepper(title: "Left Labels",
                                          value: labelBandBinding(table: selectedTable, keyPath: \.leftCols))
                        labelBandStepper(title: "Bottom Labels",
                                          value: labelBandBinding(table: selectedTable, keyPath: \.bottomRows))
                        labelBandStepper(title: "Right Labels",
                                          value: labelBandBinding(table: selectedTable, keyPath: \.rightCols))
                    }
                    .padding(8)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(6)
                }

                Text("script.py")
                    .font(.headline)
                TextEditor(text: $document.script)
                    .font(.system(.body, design: .monospaced))
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
                    runScript()
                } label: {
                    Label("Run Script", systemImage: "play.circle")
                }
                .disabled(isRunningScript)

                Button {
                    exportNumpyScript()
                } label: {
                    Label("Export NumPy", systemImage: "square.and.arrow.up")
                }
                .disabled(isRunningScript || isExporting)
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
        .onAppear {
            if selectedSheetId == nil {
                selectedSheetId = viewModel.project.sheets.first?.id
            }
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

    private func runScript() {
        guard !isRunningScript else {
            return
        }
        isRunningScript = true
        let script = document.script
        let historyJSON = ScriptComposer.historyJSON(from: script) ?? document.historyJSON
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let engine = try PythonEngineClient()
                let result = try engine.runProject(script: script)
                DispatchQueue.main.async {
                    viewModel.load(project: result.project, historyJSON: historyJSON)
                    document.historyJSON = historyJSON
                    isRunningScript = false
                    handlePendingAutoRun()
                }
            } catch {
                DispatchQueue.main.async {
                    pythonRunError = error.localizedDescription
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
}
