import SwiftUI

struct ContentView: View {
    @Binding var document: NummernDocument
    @StateObject private var viewModel: CanvasViewModel
    @State private var selectedSheetId: String?

    init(document: Binding<NummernDocument>) {
        _document = document
        _viewModel = StateObject(wrappedValue: CanvasViewModel(project: document.wrappedValue.project))
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
                Text("Event Log")
                    .font(.headline)
                TextEditor(text: .constant(viewModel.pythonLog))
                    .font(.system(.body, design: .monospaced))
                    .disabled(true)

                Text("script.py")
                    .font(.headline)
                TextEditor(text: $document.script)
                    .font(.system(.body, design: .monospaced))
            }
            .frame(minWidth: 320)
            .padding(12)
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
        .onChange(of: viewModel.project) { newValue in
            document.project = newValue
        }
        .onChange(of: viewModel.historyJSON) { newValue in
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
}
