import Foundation

enum PythonRunError: LocalizedError {
    case interpreterNotFound
    case failed(exitCode: Int32, stderr: String)
    case invalidOutput(stdout: String, stderr: String)
    case launch(Error)
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .interpreterNotFound: return "Could not locate a Python interpreter for canvassheets."
        case .failed(let code, let stderr): return "Python exited with code \(code): \(stderr)"
        case .invalidOutput: return "Python output did not contain a project JSON payload."
        case .launch(let error): return "Failed to launch Python: \(error.localizedDescription)"
        case .timedOut(let t): return "Python run timed out after \(t)s."
        }
    }

    /// The captured stderr, when the failure carries one.
    var stderrText: String? {
        switch self {
        case .failed(_, let stderr): return stderr
        case .invalidOutput(_, let stderr): return stderr
        default: return nil
        }
    }
}

/// Runs a recorded script via `python -m canvassheets run <script> --emit json`
/// and decodes the resulting `ProjectSnapshot`. The engine is plain Python — this
/// is exactly the command a user could type — so the bridge stays small.
/// Immutable after init (only spawns local processes), so safe to use from a
/// detached task.
final class PythonRunner: @unchecked Sendable {
    struct RunResult: Sendable {
        let snapshot: ProjectSnapshot
        let stdout: String
        let stderr: String
    }

    enum Emit: String {
        case json
        case numpy
        case matplotlib
    }

    private let pythonURL: URL
    private let modulePathURL: URL          // dir containing the `canvassheets` package
    private let venvURL: URL?
    let timeout: TimeInterval

    init(pythonURL: URL? = nil, modulePathURL: URL? = nil, timeout: TimeInterval = 15) throws {
        let resolvedModule = try Self.resolveModulePath(modulePathURL)
        self.modulePathURL = resolvedModule
        let resolved = Self.resolvePython(pythonURL, modulePath: resolvedModule)
        guard let exe = resolved.url else { throw PythonRunError.interpreterNotFound }
        self.pythonURL = exe
        self.venvURL = resolved.venv
        self.timeout = timeout
    }

    @discardableResult
    func run(script: String, emit: Emit = .json) throws -> RunResult {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nummern_\(UUID().uuidString).py")
        try script.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let args = ["-m", "canvassheets", "run", tmp.path, "--emit", emit.rawValue]
        let result = try launch(arguments: args)
        if result.status != 0 {
            throw PythonRunError.failed(exitCode: result.status, stderr: result.stderr)
        }
        guard emit == .json else {
            // numpy/matplotlib emit raw script text; callers handle stdout themselves.
            return RunResult(snapshot: .empty, stdout: result.stdout, stderr: result.stderr)
        }
        let snapshot = try Self.decode(result.stdout, stderr: result.stderr)
        return RunResult(snapshot: snapshot, stdout: result.stdout, stderr: result.stderr)
    }

    /// Emit a non-JSON artifact (numpy/matplotlib export) and return its text.
    func emitText(script: String, emit: Emit) throws -> String {
        let result = try run(script: script, emit: emit)
        return result.stdout
    }

    // MARK: decoding

    static func decode(_ stdout: String, stderr: String) throws -> ProjectSnapshot {
        let decoder = JSONDecoder()
        for line in stdout.split(whereSeparator: \.isNewline).reversed() {
            guard let data = line.data(using: .utf8) else { continue }
            if let snapshot = try? decoder.decode(ProjectSnapshot.self, from: data) {
                return snapshot
            }
        }
        throw PythonRunError.invalidOutput(stdout: stdout, stderr: stderr)
    }

    // MARK: resolution

    static func repoRoot() -> URL {
        // .../Nummern/Nummern/Python/PythonRunner.swift -> repo root is three levels up.
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func moduleExists(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let pkg = url.appendingPathComponent("canvassheets")
        return FileManager.default.fileExists(atPath: pkg.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func resolveModulePath(_ provided: URL?) throws -> URL {
        if let provided, moduleExists(at: provided) { return provided }
        if let env = ProcessInfo.processInfo.environment["NUMMERN_PYTHONPATH"], !env.isEmpty {
            let url = URL(fileURLWithPath: String(env.split(separator: ":").first ?? Substring(env)))
            if moduleExists(at: url) { return url }
        }
        let repoPython = repoRoot().appendingPathComponent("python")
        if moduleExists(at: repoPython) { return repoPython }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("python"),
           moduleExists(at: bundled) { return bundled }
        throw PythonRunError.interpreterNotFound
    }

    private static func resolvePython(_ provided: URL?, modulePath: URL) -> (url: URL?, venv: URL?) {
        if let provided { return (provided, venvRoot(forPython: provided)) }
        if let env = ProcessInfo.processInfo.environment["NUMMERN_PYTHON_EXECUTABLE"], !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            return (url, venvRoot(forPython: url))
        }
        // Prefer the repo venv next to the module path.
        let venv = repoRoot().appendingPathComponent(".venv")
        let venvPython = venv.appendingPathComponent("bin/python3")
        if FileManager.default.isExecutableFile(atPath: venvPython.path) {
            return (venvPython, venv)
        }
        if let virtualEnv = ProcessInfo.processInfo.environment["VIRTUAL_ENV"], !virtualEnv.isEmpty {
            let url = URL(fileURLWithPath: virtualEnv).appendingPathComponent("bin/python3")
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return (url, URL(fileURLWithPath: virtualEnv))
            }
        }
        let system = URL(fileURLWithPath: "/usr/bin/python3")
        if FileManager.default.isExecutableFile(atPath: system.path) { return (system, nil) }
        return (nil, nil)
    }

    private static func venvRoot(forPython python: URL) -> URL? {
        let bin = python.deletingLastPathComponent()
        guard bin.lastPathComponent == "bin" else { return nil }
        let root = bin.deletingLastPathComponent()
        let cfg = root.appendingPathComponent("pyvenv.cfg")
        return FileManager.default.fileExists(atPath: cfg.path) ? root : nil
    }

    private func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in env.keys where key.hasPrefix("DYLD_") || key.hasPrefix("__XPC") { env[key] = nil }
        let modulePath = modulePathURL.path
        if let existing = env["PYTHONPATH"], !existing.isEmpty {
            env["PYTHONPATH"] = "\(modulePath):\(existing)"
        } else {
            env["PYTHONPATH"] = modulePath
        }
        if let venvURL {
            env["VIRTUAL_ENV"] = venvURL.path
            let bin = venvURL.appendingPathComponent("bin").path
            env["PATH"] = "\(bin):\(env["PATH"] ?? "/usr/bin:/bin")"
        }
        return env
    }

    private func launch(arguments: [String]) throws -> (stdout: String, stderr: String, status: Int32) {
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = arguments
        process.environment = environment()

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = Pipe()

        let outData = OutputAccumulator()
        let errData = OutputAccumulator()
        outPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil } else { outData.append(d) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil } else { errData.append(d) }
        }

        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            throw PythonRunError.launch(error)
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            throw PythonRunError.timedOut(timeout)
        }
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        outData.append(outPipe.fileHandleForReading.readDataToEndOfFile())
        errData.append(errPipe.fileHandleForReading.readDataToEndOfFile())
        return (outData.string(), errData.string(), process.terminationStatus)
    }
}

private final class OutputAccumulator {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock(); data.append(chunk); lock.unlock()
    }
    func string() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
