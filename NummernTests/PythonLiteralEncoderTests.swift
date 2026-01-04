import XCTest
@testable import Nummern

final class PythonLiteralEncoderTests: XCTestCase {
    func testEncodeStringEscapesControlCharacters() {
        let input = "a\nb\rc\t\u{0007}\\'"
        let encoded = PythonLiteralEncoder.encodeString(input)

        XCTAssertTrue(encoded.hasPrefix("'"))
        XCTAssertTrue(encoded.hasSuffix("'"))
        XCTAssertFalse(encoded.contains("\n"))
        XCTAssertTrue(encoded.contains("\\n"))
        XCTAssertTrue(encoded.contains("\\r"))
        XCTAssertTrue(encoded.contains("\\t"))
        XCTAssertTrue(encoded.contains("\\x07"))
        XCTAssertTrue(encoded.contains("\\\\"))
        XCTAssertTrue(encoded.contains("\\'"))
    }

    func testEncodeDateAndTime() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2024
        components.month = 1
        components.day = 15
        let date = components.date ?? Date(timeIntervalSinceReferenceDate: 0)

        let dateEncoded = PythonLiteralEncoder.encode(.date(date))
        XCTAssertEqual(dateEncoded, "date_value('2024-01-15')")

        let timeEncoded = PythonLiteralEncoder.encode(.time(3600 + 62))
        XCTAssertEqual(timeEncoded, "time_value('01:01:02')")
    }
}
