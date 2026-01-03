import XCTest
@testable import Nummern

final class PythonBridgeTests: XCTestCase {
    func testRunScriptBuildsTables() throws {
        if ProcessInfo.processInfo.environment["RUN_PYTHON_BRIDGE_TESTS"] != "1" {
            throw XCTSkip("Set RUN_PYTHON_BRIDGE_TESTS=1 to run Python bridge integration tests.")
        }
        let script = """
        from canvassheets_api import Project, Rect

        proj = Project()
        proj.add_sheet("Sheet 1", sheet_id="sheet_1")
        table = proj.add_table(
            "sheet_1",
            table_id="table_1",
            name="Table 1",
            rect=Rect(10, 20, 300, 200),
            rows=3,
            cols=2,
            labels=dict(top=1, left=1, bottom=0, right=0)
        )
        table.set_cells({
            "body[A0]": 1,
            "body[B0]": "Hi"
        })
        """

        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoURL = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let moduleURL = repoURL.appendingPathComponent("python")

        let engine = try PythonEngineClient(moduleURL: moduleURL)
        let result = try engine.runProject(script: script)

        XCTAssertEqual(result.project.sheets.count, 1)
        XCTAssertEqual(result.project.sheets.first?.id, "sheet_1")
        XCTAssertEqual(result.project.sheets.first?.tables.count, 1)

        let table = try XCTUnwrap(result.project.sheets.first?.tables.first)
        XCTAssertEqual(table.id, "table_1")
        XCTAssertEqual(table.gridSpec.bodyRows, 3)
        XCTAssertEqual(table.gridSpec.bodyCols, 2)
        XCTAssertEqual(table.cellValues["body[A0]"], .number(1))
        XCTAssertEqual(table.cellValues["body[B0]"], .string("Hi"))
    }

    func testRunScriptHandlesLargeOutput() throws {
        if ProcessInfo.processInfo.environment["RUN_PYTHON_BRIDGE_TESTS"] != "1" {
            throw XCTSkip("Set RUN_PYTHON_BRIDGE_TESTS=1 to run Python bridge integration tests.")
        }
        let script = """
        from canvassheets_api import Project

        print("x" * 1200000)

        proj = Project()
        proj.add_sheet("Sheet 1", sheet_id="sheet_1")
        """

        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoURL = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let moduleURL = repoURL.appendingPathComponent("python")

        let engine = try PythonEngineClient(moduleURL: moduleURL)
        let result = try engine.runProject(script: script)

        XCTAssertEqual(result.project.sheets.count, 1)
        XCTAssertEqual(result.project.sheets.first?.id, "sheet_1")
    }
}
