import Foundation

struct ProjectFile: Codable, Equatable {
    var schemaVersion: Int
    var appVersion: String
    var project: ProjectModel
}

enum ProjectFileStore {
    static let schemaVersion = 1

    static func make(project: ProjectModel) -> ProjectFile {
        ProjectFile(schemaVersion: schemaVersion, appVersion: currentAppVersion(), project: project)
    }

    static func encode(_ file: ProjectFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> ProjectFile {
        let decoder = JSONDecoder()
        return try decoder.decode(ProjectFile.self, from: data)
    }

    private static func currentAppVersion() -> String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version
        }
        return "0.1.0"
    }
}
