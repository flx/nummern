import Foundation

/// Builds runnable scripts for the code panel's run controls.
enum ScriptComposer {
    /// Compose a runnable script from a selection. Prepends the user header
    /// (imports/helpers) and injects `proj = Project()` / `proj.run()` when the
    /// selection doesn't already define/finalize a project, so a fragment can be
    /// run on its own (README §11.3).
    static func selectionScript(header: String, selection: String) -> String {
        let trimmedHeader = header.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        if !trimmedHeader.isEmpty { lines.append(trimmedHeader) }
        if !mentionsProjectInit(body) { lines.append("proj = Project()") }
        lines.append(body)
        if !body.contains("proj.run()") { lines.append("proj.run()") }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func mentionsProjectInit(_ text: String) -> Bool {
        text.contains("Project()")
    }
}
