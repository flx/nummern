import Foundation

/// The canonical, ordered list of recorded commands plus the user-editable code
/// region. Renders to `script.py`: a header (imports/helpers the user may edit),
/// a single marker line, then the generated statements and a final `proj.run()`.
///
/// Every line below the marker is plain Python that runs verbatim.
final class CommandLog {
    static let marker = "# ---- Auto-generated log ----------------------------------------------"
    static let defaultHeader = """
    import pandas as pd
    from canvassheets import Project
    """

    /// Free-editing region above the marker (imports, helper functions).
    var userCode: String
    /// Generated region, in order.
    private(set) var commands: [Command]

    init(userCode: String = CommandLog.defaultHeader, commands: [Command] = []) {
        self.userCode = userCode
        self.commands = commands
    }

    func append(_ command: Command) {
        commands.append(command)
    }

    func removeLast() {
        if !commands.isEmpty { commands.removeLast() }
    }

    func replaceAll(_ newCommands: [Command]) {
        commands = newCommands
    }

    /// The generated region (without the marker), ending with `proj.run()`.
    func generatedRegion() -> String {
        var lines = ["proj = Project()"]
        lines.append(contentsOf: commands.map { $0.toPython() })
        lines.append("proj.run()")
        return lines.joined(separator: "\n")
    }

    /// The full runnable script.
    func script() -> String {
        let header = userCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(header)\n\n\(Self.marker)\n\(generatedRegion())\n"
    }

    /// Parse a script into a header + opaque generated lines. The generated lines
    /// round-trip verbatim (a full statement parser is deferred to S5); this is
    /// enough to load, render, and append below an existing script.
    static func parse(_ script: String) -> CommandLog {
        guard let markerRange = script.range(of: marker) else {
            return CommandLog(userCode: script, commands: [])
        }
        let header = String(script[..<markerRange.lowerBound])
        let generated = String(script[markerRange.upperBound...])
        var commands: [Command] = []
        for rawLine in generated.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "proj = Project()" || trimmed == "proj.run()" {
                continue
            }
            commands.append(RawLineCommand(line: trimmed))
        }
        return CommandLog(userCode: header, commands: commands)
    }
}

/// A generated line preserved verbatim from a loaded script.
struct RawLineCommand: Command {
    let line: String
    func toPython() -> String { line }
}
