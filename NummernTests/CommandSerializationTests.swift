import XCTest
@testable import Nummern

final class CommandSerializationTests: XCTestCase {
    func testPythonOutputDeterminism() {
        let mapA: [String: CellValue] = [
            "body[B1]": .number(2),
            "body[A1]": .number(1)
        ]
        let mapB: [String: CellValue] = [
            "body[A1]": .number(1),
            "body[B1]": .number(2)
        ]

        let commandA = SetCellsCommand(tableId: "table_1", cellMap: mapA)
        let commandB = SetCellsCommand(tableId: "table_1", cellMap: mapB)

        XCTAssertEqual(commandA.serializeToPython(), commandB.serializeToPython())
    }
}
