import XCTest
@testable import Nummern

final class CommandLogTests: XCTestCase {
    func testScriptHasHeaderMarkerAndRun() {
        let log = CommandLog()
        log.append(AddSheetCommand(id: "sheet_1", name: "Tab1"))
        let script = log.script()
        XCTAssertTrue(script.contains("from canvassheets import Project"))
        XCTAssertTrue(script.contains(CommandLog.marker))
        XCTAssertTrue(script.contains("proj = Project()"))
        XCTAssertTrue(script.contains(#"sheet_1 = proj.add_sheet("Tab1", id="sheet_1")"#))
        XCTAssertTrue(script.hasSuffix("proj.run()\n"))
    }

    func testParseRoundTripsGeneratedLines() {
        let original = CommandLog()
        original.append(AddSheetCommand(id: "sheet_1", name: "Tab1"))
        original.append(AddTableCommand(sheetId: "sheet_1", id: "table_1", x: 80, y: 80,
                                        rows: 3, cols: 3, labels: .init(top: 0, left: 0, bottom: 0, right: 0)))
        let script = original.script()

        let parsed = CommandLog.parse(script)
        XCTAssertEqual(parsed.script(), script)
        XCTAssertTrue(parsed.userCode.contains("from canvassheets import Project"))
    }

    func testParseWithoutMarkerKeepsAllAsUserCode() {
        let parsed = CommandLog.parse("print('hello')\n")
        XCTAssertTrue(parsed.userCode.contains("print('hello')"))
    }
}
