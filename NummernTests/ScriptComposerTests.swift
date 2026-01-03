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
        XCTAssertTrue(composed.contains(ScriptComposer.userMarker))
        XCTAssertTrue(composed.contains(ScriptComposer.logMarker))
        XCTAssertTrue(composed.contains("proj.add_sheet('Sheet 1'"))
    }

    func testComposeToleratesMarkerWhitespace() {
        let existing = """
# ---- User code (editable) ---------------------------------------------
print('user')
# ---- Auto-generated log (append-only) --------------------------------   
proj = Project()
# ---- End of script ----------------------------------------------------   
"""
        let log = "proj.add_sheet('Sheet 1', sheet_id='sheet_1')"

        let composed = ScriptComposer.compose(existing: existing, generatedLog: log)

        XCTAssertTrue(composed.contains("print('user')"))
        XCTAssertTrue(composed.contains("from canvassheets_api import"))
        XCTAssertTrue(composed.contains("proj.add_sheet('Sheet 1'"))
    }
}
