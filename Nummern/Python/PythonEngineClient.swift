import Foundation

enum PythonEngineError: LocalizedError {
    case modulePathNotFound
    case pythonFailed(exitCode: Int32, stderr: String)
    case invalidOutput(stdout: String, stderr: String)
    case invalidExportOutput(stdout: String, stderr: String)
    case unableToLaunch(Error)
    case pythonTimedOut(timeout: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .modulePathNotFound:
            return "Python module path not found."
        case .pythonFailed(let exitCode, let stderr):
            return "Python failed with exit code \(exitCode): \(stderr)"
        case .invalidOutput:
            return "Python output did not contain a valid project JSON payload."
        case .invalidExportOutput:
            return "Python output did not contain a valid export script."
        case .unableToLaunch(let error):
            return "Failed to launch Python process: \(error.localizedDescription)"
        case .pythonTimedOut(let timeout):
            return "Python run timed out after \(timeout) seconds."
        }
    }
}

final class PythonEngineClient {
    struct RunResult {
        let project: ProjectModel
        let stdout: String
        let stderr: String
    }

    private let moduleURL: URL
    private let pythonExecutableURL: URL
    private let pythonArgumentsPrefix: [String]
    private let venvURL: URL?

    init(moduleURL: URL? = nil, pythonExecutableURL: URL? = nil) throws {
        self.moduleURL = try Self.resolveModuleURL(moduleURL)
        let resolved = Self.resolvePythonExecutable(pythonExecutableURL, moduleURL: self.moduleURL)
        self.pythonExecutableURL = resolved.url
        self.pythonArgumentsPrefix = resolved.argumentsPrefix
        self.venvURL = resolved.venvURL
    }

    func runProject(script: String) throws -> RunResult {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("num_script_\(UUID().uuidString).py")
        try script.write(to: tempURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let process = Process()
        process.executableURL = pythonExecutableURL
        process.arguments = pythonArgumentsPrefix + [tempURL.path]

        var environment = sanitizedEnvironment()
        let modulePath = moduleURL.path
        if let existing = environment["PYTHONPATH"], !existing.isEmpty {
            environment["PYTHONPATH"] = "\(modulePath):\(existing)"
        } else {
            environment["PYTHONPATH"] = modulePath
        }
        if let venvURL {
            environment["VIRTUAL_ENV"] = venvURL.path
            if let existingPath = environment["PATH"], !existingPath.isEmpty {
                environment["PATH"] = "\(venvURL.appendingPathComponent("bin").path):\(existingPath)"
            }
        }
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stdinPipe.fileHandleForWriting.closeFile()

        let timeout: TimeInterval = 10
        let exitSignal = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            exitSignal.signal()
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw PythonEngineError.unableToLaunch(error)
        }

        if exitSignal.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            process.terminationHandler = nil
            throw PythonEngineError.pythonTimedOut(timeout: timeout)
        }
        process.terminationHandler = nil

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw PythonEngineError.pythonFailed(exitCode: process.terminationStatus, stderr: stderr)
        }

        let project = try Self.decodeProject(from: stdout, stderr: stderr)
        return RunResult(project: project, stdout: stdout, stderr: stderr)
    }

    func exportNumpyScript(script: String, includeFormulas: Bool = false) throws -> String {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("num_script_\(UUID().uuidString).py")
        try script.write(to: tempURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let process = Process()
        process.executableURL = pythonExecutableURL
        var args = pythonArgumentsPrefix + ["--export-numpy"]
        if includeFormulas {
            args.append("--include-formulas")
        }
        args.append(tempURL.path)
        process.arguments = args

        var environment = sanitizedEnvironment()
        let modulePath = moduleURL.path
        if let existing = environment["PYTHONPATH"], !existing.isEmpty {
            environment["PYTHONPATH"] = "\(modulePath):\(existing)"
        } else {
            environment["PYTHONPATH"] = modulePath
        }
        if let venvURL {
            environment["VIRTUAL_ENV"] = venvURL.path
            if let existingPath = environment["PATH"], !existingPath.isEmpty {
                environment["PATH"] = "\(venvURL.appendingPathComponent("bin").path):\(existingPath)"
            }
        }
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stdinPipe.fileHandleForWriting.closeFile()

        let timeout: TimeInterval = 10
        let exitSignal = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            exitSignal.signal()
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw PythonEngineError.unableToLaunch(error)
        }

        if exitSignal.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            process.terminationHandler = nil
            throw PythonEngineError.pythonTimedOut(timeout: timeout)
        }
        process.terminationHandler = nil

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw PythonEngineError.pythonFailed(exitCode: process.terminationStatus, stderr: stderr)
        }

        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PythonEngineError.invalidExportOutput(stdout: stdout, stderr: stderr)
        }
        return stdout
    }

    private static func resolveModuleURL(_ provided: URL?) throws -> URL {
        if let provided, moduleExists(at: provided) {
            return provided
        }

        if let envPath = ProcessInfo.processInfo.environment["NUMMERN_PYTHONPATH"], !envPath.isEmpty {
            let first = envPath.split(separator: ":").first.map(String.init) ?? envPath
            let url = URL(fileURLWithPath: first)
            if moduleExists(at: url) {
                return url
            }
        }

#if DEBUG
        if let debugURL = debugModuleURL(), moduleExists(at: debugURL) {
            return debugURL
        }
#endif

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let repoURL = cwd.appendingPathComponent("python")
        if moduleExists(at: repoURL),
           venvRoot(fromModuleURL: repoURL) != nil {
            return repoURL
        }

        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("python"),
           moduleExists(at: bundleURL) {
            return bundleURL
        }

        if moduleExists(at: repoURL) {
            return repoURL
        }

        throw PythonEngineError.modulePathNotFound
    }

#if DEBUG
    private static func debugModuleURL() -> URL? {
        let sourceURL = URL(fileURLWithPath: #file)
        let repoURL = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoURL.appendingPathComponent("python")
    }
#endif

    private static func resolvePythonExecutable(_ provided: URL?,
                                                moduleURL: URL) -> (url: URL, argumentsPrefix: [String], venvURL: URL?) {
        if let provided {
            return (provided, ["-m", "canvassheets_api.runner"], venvRoot(for: provided))
        }

        if let envPath = ProcessInfo.processInfo.environment["NUMMERN_PYTHON_EXECUTABLE"], !envPath.isEmpty {
            let url = URL(fileURLWithPath: envPath)
            return (url, ["-m", "canvassheets_api.runner"], venvRoot(for: url))
        }

        if let venvURL = venvRoot(fromModuleURL: moduleURL) {
            let pythonURL = venvURL.appendingPathComponent("bin/python3")
            if FileManager.default.isExecutableFile(atPath: pythonURL.path) {
                return (pythonURL, ["-m", "canvassheets_api.runner"], venvURL)
            }
        }

        if let virtualEnv = ProcessInfo.processInfo.environment["VIRTUAL_ENV"], !virtualEnv.isEmpty {
            let venvURL = URL(fileURLWithPath: virtualEnv)
            let pythonURL = venvURL.appendingPathComponent("bin/python3")
            if FileManager.default.isExecutableFile(atPath: pythonURL.path) {
                return (pythonURL, ["-m", "canvassheets_api.runner"], venvURL)
            }
        }

        let systemPython = URL(fileURLWithPath: "/usr/bin/python3")
        if FileManager.default.isExecutableFile(atPath: systemPython.path) {
            return (systemPython, ["-m", "canvassheets_api.runner"], nil)
        }

        return (URL(fileURLWithPath: "/usr/bin/env"), ["python3", "-m", "canvassheets_api.runner"], nil)
    }

    private static func moduleExists(at url: URL) -> Bool {
        let moduleURL = url.appendingPathComponent("canvassheets_api")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: moduleURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func venvRoot(fromModuleURL moduleURL: URL) -> URL? {
        let root: URL
        if moduleURL.lastPathComponent == "python" {
            root = moduleURL.deletingLastPathComponent()
        } else {
            root = moduleURL
        }
        let venvURL = root.appendingPathComponent(".venv")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: venvURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        guard isVenvRoot(venvURL) else {
            return nil
        }
        return venvURL
    }

    private static func venvRoot(for pythonURL: URL) -> URL? {
        let binURL = pythonURL.deletingLastPathComponent()
        guard binURL.lastPathComponent == "bin" else {
            return nil
        }
        let venvURL = binURL.deletingLastPathComponent()
        return isVenvRoot(venvURL) ? venvURL : nil
    }

    private static func isVenvRoot(_ url: URL) -> Bool {
        let configURL = url.appendingPathComponent("pyvenv.cfg")
        return FileManager.default.fileExists(atPath: configURL.path)
    }

    private static func decodeProject(from stdout: String, stderr: String) throws -> ProjectModel {
        let lines = stdout.split(whereSeparator: \.isNewline).map(String.init)
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8) else {
                continue
            }
            if let project = try? JSONDecoder().decode(ProjectModel.self, from: data) {
                return project
            }
        }
        throw PythonEngineError.invalidOutput(stdout: stdout, stderr: stderr)
    }

    private func sanitizedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let blockedPrefixes = ["DYLD_", "LLVM_"]
        let blockedKeys = [
            "XCTestConfigurationFilePath",
            "XCTestBundlePath",
            "OS_ACTIVITY_DT_MODE",
            "XCInjectBundleInto",
            "XCInjectBundle",
        ]
        for key in environment.keys {
            if blockedKeys.contains(key) || blockedPrefixes.contains(where: { key.hasPrefix($0) }) {
                environment.removeValue(forKey: key)
            }
        }
        return environment
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let exitSignal = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            exitSignal.signal()
        }
        let result = exitSignal.wait(timeout: .now() + timeout) == .success
        process.terminationHandler = nil
        return result
    }
}
