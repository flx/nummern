import SwiftUI
import UniformTypeIdentifiers

struct ScriptComposer {
    static let userMarker = "# ---- User code (editable) ---------------------------------------------"
    static let logMarker = "# ---- Auto-generated log (append-only) --------------------------------"
    static let endMarker = "# ---- End of script ----------------------------------------------------"

    static func compose(existing: String, generatedLog: String) -> String {
        let trimmedLog = generatedLog.trimmingCharacters(in: .whitespacesAndNewlines)
        let logLines = buildLogLines(from: trimmedLog)
        let lines = existing.components(separatedBy: .newlines)

        guard let logIndex = lines.firstIndex(of: logMarker),
              let endIndex = lines.firstIndex(of: endMarker),
              logIndex < endIndex else {
            return defaultScript(with: trimmedLog)
        }

        let prefix = lines[0...logIndex]
        let suffix = lines[endIndex...]
        let updated = Array(prefix) + logLines + Array(suffix)
        return updated.joined(separator: "\n")
    }

    static func defaultScript(with generatedLog: String = "") -> String {
        let trimmedLog = generatedLog.trimmingCharacters(in: .whitespacesAndNewlines)
        let logLines = buildLogLines(from: trimmedLog)
        let lines = [
            userMarker,
            "import numpy as np",
            "from canvassheets_api import Project, Rect, formula, table_context, label_context, c_range, c_sum, c_avg, c_min, c_max, c_count, c_counta, c_if, c_and, c_or, c_not",
            "",
            logMarker,
        ] + logLines + [
            endMarker
        ]
        return lines.joined(separator: "\n")
    }

    private static func buildLogLines(from trimmedLog: String) -> [String] {
        var logLines = ["from canvassheets_api import formula, table_context, label_context, c_range, c_sum, c_avg, c_min, c_max, c_count, c_counta, c_if, c_and, c_or, c_not", "proj = Project()", ""]
        if !trimmedLog.isEmpty {
            logLines.append(contentsOf: trimmedLog.components(separatedBy: .newlines))
        }
        return logLines
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
