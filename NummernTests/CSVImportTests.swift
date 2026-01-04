import XCTest
@testable import Nummern

final class CSVImportTests: XCTestCase {
    func testInferTypesOnImport() {
        let csv = """
2024-01-01,12:30:00,42,hello
2024-01-02,13:45:00,43,world
"""
        guard let tableImport = CSVTableImporter.parse(csv) else {
            XCTFail("Expected CSV import")
            return
        }
        XCTAssertEqual(tableImport.columnTypes, [.date, .time, .number, .string])
        if case .date = tableImport.values[0][0] {
            // ok
        } else {
            XCTFail("Expected date value")
        }
        if case .time = tableImport.values[0][1] {
            // ok
        } else {
            XCTFail("Expected time value")
        }
        XCTAssertEqual(tableImport.values[0][2], .number(42))
        XCTAssertEqual(tableImport.values[0][3], .string("hello"))
    }
}
