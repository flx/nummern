import SwiftUI

struct ContentView: View {
    @ObservedObject var document: NummernDocument
    @State private var showCode = false

    var body: some View {
        VStack(spacing: 0) {
            sheetTabs
            Divider()
            FormulaBar(document: document)
            Divider()
            HSplitView {
                CanvasView(document: document)
                    .frame(minWidth: 480)
                if showCode {
                    CodePanel(document: document).frame(minWidth: 320)
                }
            }
            if let error = document.lastError {
                errorBar(error)
            }
        }
        .toolbar { toolbarContent }
        .frame(minWidth: 800, minHeight: 560)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button { document.addSheet(name: "Sheet \(document.project.sheets.count + 1)") } label: {
                Label("Add Sheet", systemImage: "plus.rectangle.on.folder")
            }
            Button { document.addTable() } label: {
                Label("Add Table", systemImage: "tablecells")
            }
            .disabled(document.project.sheets.isEmpty)
            Spacer()
            if document.isRunning { ProgressView().controlSize(.small) }
            Button { showCode.toggle() } label: {
                Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        }
    }

    private var sheetTabs: some View {
        HStack(spacing: 6) {
            ForEach(document.project.sheets) { sheet in
                Button(sheet.name) { document.selectedSheetId = sheet.id }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(sheet.id == document.selectedSheetId
                                ? Color.accentColor.opacity(0.2) : Color.clear)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func errorBar(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).lineLimit(2)
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
    }
}

/// Edits the selected cell. A leading `=` records a Python expression (`SetExpr`),
/// otherwise a literal value (`SetLiteral`); both re-run the engine.
struct FormulaBar: View {
    @ObservedObject var document: NummernDocument
    @State private var text: String = ""

    private var label: String {
        guard let sel = document.selectedCell else { return "—" }
        return "\(sel.tableId) · \(CellAddress.cellRef(row: sel.row, col: sel.col))"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            TextField("value or =python expression", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .disabled(document.selectedCell == nil)
                .onSubmit { document.commitCellInput(text) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .onChange(of: document.selection) { _, _ in text = document.selectedCellText() }
    }
}

/// Editable code panel: the script (header + generated region), Run controls,
/// and a console. Editing + Run All re-parses the generated region back into the
/// command log so later UI edits append to what was just run.
struct CodePanel: View {
    @ObservedObject var document: NummernDocument
    @State private var selectedRange = NSRange(location: 0, length: 0)

    private var hasSelection: Bool { selectedRange.length > 0 }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ScriptEditor(text: $document.scriptText, selectedRange: $selectedRange)
                .frame(minHeight: 200)
            Divider()
            console
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button("Run All") { document.runAll() }
                .keyboardShortcut("r", modifiers: [.command])
            Button("Run Selection") {
                document.runSelection(document.scriptText.substring(nsRange: selectedRange))
            }
            .disabled(!hasSelection)
            Button("Reset Runtime") { document.resetRuntime() }
            Spacer()
            if document.isRunning { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var console: some View {
        ScrollView {
            Text(document.consoleText.isEmpty ? "—" : document.consoleText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(height: 110)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
