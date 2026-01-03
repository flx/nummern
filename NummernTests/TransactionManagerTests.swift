import XCTest
@testable import Nummern

final class TransactionManagerTests: XCTestCase {
    func testEditCellGroupsIntoSingleTransaction() {
        let manager = TransactionManager()
        manager.begin(kind: .cellEdit)

        manager.record(SetCellsCommand(tableId: "table_1", cellMap: ["body[A0]": .number(1)]))
        manager.record(SetCellsCommand(tableId: "table_1", cellMap: ["body[B0]": .number(2)]))

        let transaction = manager.commit()

        XCTAssertNotNil(transaction)
        XCTAssertEqual(transaction?.commands.count, 1)
        let merged = transaction?.commands.first as? SetCellsCommand
        XCTAssertEqual(merged?.cellMap.count, 2)
    }
}
