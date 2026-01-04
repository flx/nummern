import XCTest
@testable import Nummern

final class ScriptComposerTests: XCTestCase {
    func testComposePreservesUserCodeWhenMarkersMissing() {
        let existing = """
print('hello')
value = 1
"""
        let log = "proj.add_sheet('Sheet 1', sheet_id='sheet_1')"

        let composed = ScriptComposer.compose(existing: existing, generatedLog: log)

        XCTAssertTrue(composed.contains("print('hello')"))
        XCTAssertTrue(composed.contains(ScriptComposer.logMarker))
        XCTAssertTrue(composed.contains("proj.add_sheet('Sheet 1'"))
    }

    func testComposeToleratesMarkerWhitespace() {
        let existing = """
print('user')
# ---- Auto-generated log ----------------------------------------------   
proj = Project()
"""
        let log = "proj.add_sheet('Sheet 1', sheet_id='sheet_1')"

        let composed = ScriptComposer.compose(existing: existing, generatedLog: log)

        XCTAssertTrue(composed.contains("print('user')"))
        XCTAssertTrue(composed.contains("proj.add_sheet('Sheet 1'"))
    }

    func testExtractGeneratedLogStripsHeader() {
        let script = """
print('user')
# ---- Auto-generated log ----------------------------------------------
proj = Project()

proj.add_sheet('Sheet 1', sheet_id='sheet_1')
"""

        let log = ScriptComposer.extractGeneratedLog(from: script)
        XCTAssertEqual(log, "proj.add_sheet('Sheet 1', sheet_id='sheet_1')")
    }

    func testHistoryJSONFromScriptUsesLogLines() throws {
        let script = """
# ---- Auto-generated log ----------------------------------------------
proj = Project()

proj.add_sheet('Sheet 1', sheet_id='sheet_1')
proj.add_table('sheet_1', table_id='table_1', name='table_1', x=0, y=0, rows=1, cols=1, labels=dict(top=0, left=0, bottom=0, right=0))
"""

        guard let json = ScriptComposer.historyJSON(from: script),
              let data = json.data(using: .utf8) else {
            XCTFail("Expected history JSON")
            return
        }
        let history = try JSONDecoder().decode(CommandHistory.self, from: data)
        XCTAssertEqual(history.commands.count, 2)
        XCTAssertTrue(history.commands.first?.contains("proj.add_sheet") ?? false)
        XCTAssertTrue(history.commands.last?.contains("proj.add_table") ?? false)
    }

    func testExtractGeneratedLogDropsTableAliases() {
        let script = """
# ---- Auto-generated log ----------------------------------------------
proj = Project()

proj.add_table('sheet_1', table_id='table_1', name='table_1', x=0, y=0, rows=1, cols=1, labels=dict(top=0, left=0, bottom=0, right=0))
table_1 = proj.table('table_1')
table_1=proj.table('table_1')
t = proj.table('table_1')
with table_context(t):
    a0 = 1
"""

        let log = ScriptComposer.extractGeneratedLog(from: script)
        XCTAssertEqual(log, """
proj.add_table('sheet_1', table_id='table_1', name='table_1', x=0, y=0, rows=1, cols=1, labels=dict(top=0, left=0, bottom=0, right=0))
t = proj.table('table_1')
with table_context(t):
    a0 = 1
""")
    }

    func testSelectionScriptAddsProjectInitWhenMissing() {
        let script = """
import numpy as np
# ---- Auto-generated log ----------------------------------------------
proj = Project()
proj.add_sheet('Sheet 1', sheet_id='sheet_1')
"""
        let range = (script as NSString).range(of: "proj.add_sheet('Sheet 1', sheet_id='sheet_1')")
        let selectionScript = ScriptComposer.selectionScript(from: script, selectionRange: range)

        XCTAssertNotNil(selectionScript)
        XCTAssertTrue(selectionScript?.contains("import numpy as np") ?? false)
        XCTAssertTrue(selectionScript?.contains("proj = Project()") ?? false)
        XCTAssertTrue(selectionScript?.contains("proj.add_sheet('Sheet 1'") ?? false)
    }

    func testSelectionScriptUsesImportHeaderWhenMarkerMissing() {
        let script = """
import numpy as np
from canvassheets_api import Project

proj = Project()
proj.add_sheet('Sheet 1', sheet_id='sheet_1')
"""
        let range = (script as NSString).range(of: "proj.add_sheet('Sheet 1', sheet_id='sheet_1')")
        let selectionScript = ScriptComposer.selectionScript(from: script, selectionRange: range)

        XCTAssertNotNil(selectionScript)
        XCTAssertTrue(selectionScript?.contains("import numpy as np") ?? false)
        XCTAssertTrue(selectionScript?.contains("from canvassheets_api import Project") ?? false)
        XCTAssertTrue(selectionScript?.contains("proj = Project()") ?? false)
    }
}
