import SwiftUI
import UniformTypeIdentifiers

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
        """
        # ---- User code (editable) ---------------------------------------------
        import numpy as np
        from canvassheets_api import Project, Rect

        # ---- Auto-generated log (append-only) --------------------------------
        proj = Project()

        # ---- End of script ----------------------------------------------------
        """
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
    static var nummernDocument = UTType(exportedAs: "com.digitalhandstand.nummern.document")
}
