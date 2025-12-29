import SwiftUI

struct ContentView: View {
    @Binding var document: NummernDocument
    @StateObject private var viewModel: CanvasViewModel
    @State private var selectedSheetId: String?

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
                        Text(selectedTable.name)
                            .font(.subheadline)
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

                Text("Event Log")
                    .font(.headline)
                ScrollView {
                    Text(viewModel.pythonLog)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 140)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)

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
        .onAppear {
            if selectedSheetId == nil {
                selectedSheetId = viewModel.project.sheets.first?.id
            }
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
    private func labelBandStepper(title: String, value: Binding<Int>) -> some View {
        Stepper("\(title): \(value.wrappedValue)", value: value, in: 0...10)
    }
}
