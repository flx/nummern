import SwiftUI

struct ContentView: View {
    @Binding var document: NummernDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nummern document placeholder")
                .font(.headline)
            Text("Sheets: \(document.project.sheets.count)")
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 8) {
                Text("project.json")
                    .font(.subheadline)
                TextEditor(text: .constant(document.projectJSONString))
                    .font(.system(.body, design: .monospaced))
                    .disabled(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("script.py")
                    .font(.subheadline)
                TextEditor(text: $document.script)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 640)
    }
}
