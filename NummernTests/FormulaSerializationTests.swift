import XCTest
@testable import Nummern

final class FormulaSerializationTests: XCTestCase {
    func testAggregateFormulaUsesHelper() {
        let command = SetFormulaCommand(
            tableId: "table_1",
            targetRange: "body[C1]",
            formula: "=SUM(A1:B2)"
        )

        let python = command.serializeToPython()
        XCTAssertTrue(python.contains("c_sum('a1:b2')"))
        XCTAssertFalse(python.contains("formula("))
    }

    func testCrossTableFormulaUsesInlineExpression() {
        let command = SetFormulaCommand(
            tableId: "table_1",
            targetRange: "body[B2]",
            formula: "=B1+table_2.B3"
        )

        let python = command.serializeToPython()
        XCTAssertTrue(python.contains("b2 = b1+table_2.b3"))
        XCTAssertFalse(python.contains("formula("))
    }
}
