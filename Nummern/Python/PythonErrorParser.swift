import Foundation

/// Extracts a line number and message from a Python traceback so run errors can
/// be shown against the script the user sees. The script is written to a temp
/// file with the same line numbering as the editor, so the deepest frame in that
/// file maps directly to an editor line.
enum PythonErrorParser {
    struct ParsedError: Equatable {
        let line: Int?
        let message: String

        func displayString() -> String {
            if let line { return "Line \(line): \(message)" }
            return message
        }
    }

    private static let fileLine = try! NSRegularExpression(
        pattern: #"File \"([^\"]*)\", line (\d+)"#)

    static func parse(_ stderr: String) -> ParsedError {
        let lines = stderr.components(separatedBy: "\n")
        var lastFrameLine: Int?
        var scriptFrameLine: Int?

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = fileLine.firstMatch(in: line, range: range),
                  let fileRange = Range(match.range(at: 1), in: line),
                  let numRange = Range(match.range(at: 2), in: line),
                  let n = Int(line[numRange]) else { continue }
            lastFrameLine = n
            let file = String(line[fileRange])
            // Prefer the frame inside the user's (temp) script over library frames.
            if file.contains("nummern_") || file.hasSuffix("script.py") {
                scriptFrameLine = n
            }
        }

        var message = "Run failed."
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("File \"") || trimmed.hasPrefix("Traceback") { continue }
            // The exception line looks like "SomeError: message" (not indented source).
            if line.first == " " && !trimmed.contains(":") { continue }
            message = trimmed
            break
        }
        return ParsedError(line: scriptFrameLine ?? lastFrameLine, message: message)
    }
}
