import XCTest
@testable import Nummern

final class CellValueParsingTests: XCTestCase {
    func testDateParsingIso() {
        guard case .date(let parsed) = CellValue.fromUserInput("2024-01-15", columnType: .date) else {
            XCTFail("Expected date value")
            return
        }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2024
        components.month = 1
        components.day = 15
        let expected = components.date
        XCTAssertEqual(parsed, expected)
    }

    func testTimeParsingIso() {
        guard case .time(let seconds) = CellValue.fromUserInput("13:45:30", columnType: .time) else {
            XCTFail("Expected time value")
            return
        }
        XCTAssertEqual(seconds, 13 * 3600 + 45 * 60 + 30, accuracy: 0.1)
    }

    func testCurrencyParsingUsesLocaleFormatter() {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .currency
        guard let sample = formatter.string(from: 12.34) else {
            XCTFail("Currency formatter did not return a string")
            return
        }
        guard case .number(let value) = CellValue.fromUserInput(sample, columnType: .currency) else {
            XCTFail("Expected numeric currency value")
            return
        }
        XCTAssertEqual(value, 12.34, accuracy: 0.01)
    }

    func testPercentageParsingUsesLocaleFormatter() {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .percent
        guard let sample = formatter.string(from: 0.25) else {
            XCTFail("Percent formatter did not return a string")
            return
        }
        guard case .number(let value) = CellValue.fromUserInput(sample, columnType: .percentage) else {
            XCTFail("Expected numeric percent value")
            return
        }
        XCTAssertEqual(value, 0.25, accuracy: 0.001)
    }
}
