import XCTest
@testable import Nummern

final class CommandTests: XCTestCase {
    func testAddSheet() {
        let cmd = AddSheetCommand(id: "sheet_1", name: "Tab1")
        XCTAssertEqual(cmd.toPython(), #"sheet_1 = proj.add_sheet("Tab1", id="sheet_1")"#)
    }

    func testAddTable() {
        let cmd = AddTableCommand(sheetId: "sheet_1", id: "table_1", x: 120, y: 120,
                                  rows: 4, cols: 6,
                                  labels: .init(top: 1, left: 1, bottom: 0, right: 0))
        XCTAssertEqual(cmd.toPython(),
            #"table_1 = proj.add_table(sheet_1, id="table_1", x=120, y=120, rows=4, cols=6, labels=dict(top=1, left=1, bottom=0, right=0))"#)
    }

    func testSetLiteralGrid() {
        let cmd = SetLiteralCommand(tableId: "table_1", range: "A0:B1",
                                    values: [[.number(1), .number(2)], [.string("x"), .empty]])
        XCTAssertEqual(cmd.toPython(), #"table_1["A0:B1"] = [[1, 2], ["x", None]]"#)
    }

    func testSetExprIsPlainPython() {
        let cmd = SetExprCommand(tableId: "table_1", target: "F", expr: #"table_1["B"] + table_1["C"]"#)
        XCTAssertEqual(cmd.toPython(), #"table_1["F"] = table_1["B"] + table_1["C"]"#)
    }

    func testSetLabelBand() {
        let cmd = SetLabelBandCommand(tableId: "t", region: "top", values: ["Region", "Q1"])
        XCTAssertEqual(cmd.toPython(), #"t.top[:] = ["Region", "Q1"]"#)
    }

    func testAddSummary() {
        let cmd = AddSummaryCommand(sheetId: "sheet_1", id: "table_2", sourceId: "table_1",
                                    groupBy: ["Region"], values: [(col: "Revenue", agg: "sum")])
        XCTAssertEqual(cmd.toPython(),
            #"table_2 = proj.add_summary(sheet_1, "table_1", group_by=["Region"], values={"Revenue": "sum"}, id="table_2")"#)
    }

    func testStringEscaping() {
        XCTAssertEqual(PythonLiteralEncoder.string("a\"b\n"), "\"a\\\"b\\n\"")
    }

    func testNumberFormatting() {
        XCTAssertEqual(PythonLiteralEncoder.number(5), "5")
        XCTAssertEqual(PythonLiteralEncoder.number(2.5), "2.5")
    }
}
