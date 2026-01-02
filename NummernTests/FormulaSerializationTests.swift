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
}
