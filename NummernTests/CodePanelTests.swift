import XCTest
@testable import Nummern

final class CodePanelTests: XCTestCase {
    // MARK: PythonErrorParser

    func testParsesTracebackLineAndMessage() {
        let stderr = """
        Traceback (most recent call last):
          File "/var/folders/x/nummern_ABC.py", line 7, in <module>
            t["F"] = t["B"] + t["Q"]
          File "/repo/python/canvassheets/table.py", line 200, in __getitem__
            raise KeyError(...)
        KeyError: 'No column named Q'
        """
        let parsed = PythonErrorParser.parse(stderr)
        XCTAssertEqual(parsed.line, 7)   // prefers the user script frame, not the library frame
        XCTAssertTrue(parsed.message.contains("KeyError"))
        XCTAssertEqual(parsed.displayString(), "Line 7: KeyError: 'No column named Q'")
    }

    func testParseWithoutTraceback() {
        let parsed = PythonErrorParser.parse("some opaque failure\n")
        XCTAssertNil(parsed.line)
        XCTAssertEqual(parsed.message, "some opaque failure")
    }

    // MARK: ScriptComposer

    func testSelectionInjectsProjectAndRun() {
        let script = ScriptComposer.selectionScript(
            header: "from canvassheets import Project",
            selection: #"s = proj.add_sheet("T")"#)
        XCTAssertTrue(script.contains("from canvassheets import Project"))
        XCTAssertTrue(script.contains("proj = Project()"))
        XCTAssertTrue(script.contains(#"s = proj.add_sheet("T")"#))
        XCTAssertTrue(script.hasSuffix("proj.run()\n"))
    }

    func testSelectionDoesNotDoubleInject() {
        let selection = """
        proj = Project()
        proj.add_sheet("T")
        proj.run()
        """
        let script = ScriptComposer.selectionScript(header: "import x", selection: selection)
        XCTAssertEqual(script.components(separatedBy: "proj = Project()").count - 1, 1)
        XCTAssertEqual(script.components(separatedBy: "proj.run()").count - 1, 1)
    }
}
