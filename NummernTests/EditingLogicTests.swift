import XCTest
@testable import Nummern

final class EditingLogicTests: XCTestCase {
    func testCellAddress() {
        XCTAssertEqual(CellAddress.columnLabel(0), "A")
        XCTAssertEqual(CellAddress.columnLabel(26), "AA")
        XCTAssertEqual(CellAddress.columnIndex("AA"), 26)
        XCTAssertEqual(CellAddress.parseCell("B3")?.row, 3)
        XCTAssertEqual(CellAddress.parseCell("B3")?.col, 1)
        XCTAssertEqual(CellAddress.cellRef(row: 3, col: 5), "F3")
        let r = CellAddress.parseRange("C9:A0")
        XCTAssertEqual(r?.r0, 0); XCTAssertEqual(r?.c1, 2); XCTAssertEqual(r?.r1, 9)
    }

    func testCellInput() {
        XCTAssertEqual(CellInput.parse("42"), .literal(.number(42)))
        XCTAssertEqual(CellInput.parse("hi"), .literal(.string("hi")))
        XCTAssertEqual(CellInput.parse(""), .literal(.empty))
        XCTAssertEqual(CellInput.parse("true"), .literal(.bool(true)))
        XCTAssertEqual(CellInput.parse(#"=table_1["A"].sum()"#), .formula(#"table_1["A"].sum()"#))
    }

    func testClipboardParsing() {
        XCTAssertEqual(ClipboardParser.parse("1\t2\n3\thi"),
                       [[.number(1), .number(2)], [.number(3), .string("hi")]])
        XCTAssertEqual(ClipboardParser.parse("a,b\n1,2"),
                       [[.string("a"), .string("b")], [.number(1), .number(2)]])
    }

    func testFormulaProvenance() {
        let cmds: [Command] = [
            SetLiteralCommand(tableId: "t", range: "A0:A3", values: [[.number(1)]]),
            SetExprCommand(tableId: "t", target: "F", expr: #"t["A"] * 2"#),
            SetLiteralCommand(tableId: "t", range: "A0", values: [[.number(9)]]),
        ]
        XCTAssertEqual(FormulaProvenance.expression(for: "t", ref: "F2", in: cmds), #"t["A"] * 2"#)
        XCTAssertNil(FormulaProvenance.expression(for: "t", ref: "A0", in: cmds))
        XCTAssertTrue(FormulaProvenance.covers("F0:F9", (row: 3, col: 5)))
        XCTAssertTrue(FormulaProvenance.covers("F", (row: 99, col: 5)))
        XCTAssertFalse(FormulaProvenance.covers("F", (row: 0, col: 4)))
    }
}
