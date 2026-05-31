import SwiftUI

struct ContentView: View {
    @ObservedObject var document: NummernDocument
    @State private var showCode = false

    var body: some View {
        VStack(spacing: 0) {
            sheetTabs
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

/// Minimal read-only code view (editable Run controls land in S5).
struct CodePanel: View {
    @ObservedObject var document: NummernDocument
    var body: some View {
        ScrollView {
            Text(document.log.script())
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
