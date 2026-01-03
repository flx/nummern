import XCTest
@testable import Nummern

final class FormulaSerializationTests: XCTestCase {
    func testAggregateFormulaUsesHelper() {
        let command = SetFormulaCommand(
            tableId: "table_1",
            targetRange: "body[C0]",
            formula: "=SUM(A0:B1)"
        )

        let python = command.serializeToPython()
        XCTAssertTrue(python.contains("c_sum('a0:b1')"))
        XCTAssertFalse(python.contains("formula("))
    }

    func testCrossTableFormulaUsesInlineExpression() {
        let command = SetFormulaCommand(
            tableId: "table_1",
            targetRange: "body[B1]",
            formula: "=B0+table_2.B2"
        )

        let python = command.serializeToPython()
        XCTAssertTrue(python.contains("b1 = b0+table_2.b2"))
        XCTAssertFalse(python.contains("formula("))
    }

    func testLabelFormulaUsesTableContextSugar() {
        let command = SetFormulaCommand(
            tableId: "table_1",
            targetRange: "top_labels[A0]",
            formula: "=SUM(A0:A9)"
        )

        let python = command.serializeToPython()
        XCTAssertTrue(python.contains("with table_context(t):"))
        XCTAssertTrue(python.contains("top_labels.a0 = c_sum('a0:a9')"))
    }
}
