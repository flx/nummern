import SwiftUI
import UniformTypeIdentifiers

struct NummernDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.nummernDocument] }

    var projectJSON: String
    var script: String

    init(projectJSON: String = NummernDocument.defaultProjectJSON(),
         script: String = NummernDocument.defaultScript()) {
        self.projectJSON = projectJSON
        self.script = script
    }

    init(configuration: ReadConfiguration) throws {
        let wrapper = configuration.file
        if wrapper.isDirectory {
            let children = wrapper.fileWrappers ?? [:]
            if let data = children["project.json"]?.regularFileContents,
               let string = String(data: data, encoding: .utf8) {
                projectJSON = string
            } else {
                projectJSON = NummernDocument.defaultProjectJSON()
            }
            if let data = children["script.py"]?.regularFileContents,
               let string = String(data: data, encoding: .utf8) {
                script = string
            } else {
                script = NummernDocument.defaultScript()
            }
        } else if let data = wrapper.regularFileContents,
                  let string = String(data: data, encoding: .utf8) {
            projectJSON = NummernDocument.defaultProjectJSON()
            script = string
        } else {
            projectJSON = NummernDocument.defaultProjectJSON()
            script = NummernDocument.defaultScript()
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let projectData = projectJSON.data(using: .utf8) ?? Data()
        let scriptData = script.data(using: .utf8) ?? Data()
        let wrappers: [String: FileWrapper] = [
            "project.json": .init(regularFileWithContents: projectData),
            "script.py": .init(regularFileWithContents: scriptData)
        ]
        return .init(directoryWithFileWrappers: wrappers)
    }

    private static func defaultProjectJSON() -> String {
        """
        {
          \"schema_version\": 1,
          \"sheets\": [],
          \"objects\": []
        }
        """
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
}

extension UTType {
    static var nummernDocument = UTType(exportedAs: "com.digitalhandstand.nummern.document")
}
