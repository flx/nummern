import SwiftUI
import UniformTypeIdentifiers

struct ScriptComposer {
    static let logMarker = "# ---- Auto-generated log ----------------------------------------------"

    static func compose(existing: String, generatedLog: String) -> String {
        let trimmedLog = generatedLog.trimmingCharacters(in: .whitespacesAndNewlines)
        let logLines = buildLogLines(from: trimmedLog)
        let lines = existing.components(separatedBy: .newlines)

        guard let logIndex = markerIndex(logMarker, in: lines) else {
            return composePreservingUser(existing: existing, logLines: logLines)
        }

        let prefix = lines[0...logIndex]
        let updated = Array(prefix) + logLines
        return updated.joined(separator: "\n")
    }

    static func defaultScript(with generatedLog: String = "") -> String {
        let trimmedLog = generatedLog.trimmingCharacters(in: .whitespacesAndNewlines)
        let logLines = buildLogLines(from: trimmedLog)
        let lines = [
            "import numpy as np",
            "from canvassheets_api import Project, Rect, formula, table_context, label_context, c_range, c_sum, c_avg, c_min, c_max, c_count, c_counta, c_if, c_and, c_or, c_not, date_value, time_value",
            "",
            logMarker,
        ] + logLines
        return lines.joined(separator: "\n")
    }

    private static func buildLogLines(from trimmedLog: String) -> [String] {
        var logLines = ["proj = Project()"]
        if !trimmedLog.isEmpty {
            logLines.append(contentsOf: trimmedLog.components(separatedBy: .newlines))
        }
        return logLines
    }

    static func extractGeneratedLog(from script: String) -> String? {
        let lines = script.components(separatedBy: .newlines)
        guard let logIndex = markerIndex(logMarker, in: lines),
              logIndex + 1 < lines.count else {
            return nil
        }

        var logLines = Array(lines[(logIndex + 1)...])
        while let first = logLines.first,
              first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logLines.removeFirst()
        }
        while let last = logLines.last,
              last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logLines.removeLast()
        }

        if let first = logLines.first,
           first.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("proj = Project()") {
            logLines.removeFirst()
        }
        if let first = logLines.first,
           first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logLines.removeFirst()
        }

        logLines = logLines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return false
            }
            return !isTableAliasLine(trimmed)
        }

        let trimmed = logLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed
    }

    static func historyJSON(from script: String) -> String? {
        guard let log = extractGeneratedLog(from: script) else {
            return nil
        }
        let commands = log.isEmpty ? [] : log.components(separatedBy: .newlines)
        let history = CommandHistory(commands: commands)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(history) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func isTableAliasLine(_ line: String) -> Bool {
        let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return false
        }
        let lhs = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard lhs != "t", !lhs.isEmpty else {
            return false
        }
        let rhs = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard rhs.hasPrefix("proj.table(") else {
            return false
        }
        return lhs.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
    }

    private static func markerIndex(_ marker: String, in lines: [String]) -> Int? {
        lines.firstIndex { line in
            line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(marker)
        }
    }

    private static func composePreservingUser(existing: String, logLines: [String]) -> String {
        let existingLines = existing.components(separatedBy: .newlines)
        var lines: [String] = []
        lines.append(contentsOf: existingLines)
        if let last = lines.last, !last.isEmpty {
            lines.append("")
        }
        lines.append(logMarker)
        lines.append(contentsOf: logLines)
        return lines.joined(separator: "\n")
    }
}

struct NummernDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.nummernDocument] }

    var project: ProjectModel
    var script: String
    var historyJSON: String?

    init(project: ProjectModel = ProjectModel(),
         script: String = NummernDocument.defaultScript(),
         historyJSON: String? = nil) {
        self.project = project
        self.script = script
        self.historyJSON = historyJSON
    }

    init(configuration: ReadConfiguration) throws {
        let wrapper = configuration.file
        if wrapper.isDirectory {
            let children = wrapper.fileWrappers ?? [:]
            if let data = children["project.json"]?.regularFileContents {
                project = (try? ProjectFileStore.decode(data))?.project ?? ProjectModel()
            } else {
                project = ProjectModel()
            }
            if let data = children["script.py"]?.regularFileContents,
               let string = String(data: data, encoding: .utf8) {
                script = string
            } else {
                script = NummernDocument.defaultScript()
            }
            if let data = children["history.json"]?.regularFileContents,
               let string = String(data: data, encoding: .utf8) {
                historyJSON = string
            } else {
                historyJSON = nil
            }
        } else if let data = wrapper.regularFileContents,
                  let string = String(data: data, encoding: .utf8) {
            project = ProjectModel()
            script = string
            historyJSON = nil
        } else {
            project = ProjectModel()
            script = NummernDocument.defaultScript()
            historyJSON = nil
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try makeFileWrapper()
    }

    func makeFileWrapper() throws -> FileWrapper {
        let projectFile = ProjectFileStore.make(project: project)
        let projectData = try ProjectFileStore.encode(projectFile)
        let scriptData = script.data(using: .utf8) ?? Data()
        var wrappers: [String: FileWrapper] = [
            "project.json": .init(regularFileWithContents: projectData),
            "script.py": .init(regularFileWithContents: scriptData)
        ]
        if let historyJSON,
           let historyData = historyJSON.data(using: .utf8) {
            wrappers["history.json"] = .init(regularFileWithContents: historyData)
        }
        return .init(directoryWithFileWrappers: wrappers)
    }

    private static func defaultScript() -> String {
        ScriptComposer.defaultScript()
    }

    var projectJSONString: String {
        let file = ProjectFileStore.make(project: project)
        guard let data = try? ProjectFileStore.encode(file) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

extension UTType {
    static var nummernDocument: UTType {
        UTType(exportedAs: "com.digitalhandstand.nummern.document", conformingTo: .package)
    }
}
