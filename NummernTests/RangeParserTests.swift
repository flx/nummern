import XCTest
@testable import Nummern

final class RangeParserTests: XCTestCase {
    func testBodyAddress() throws {
        let range = try RangeParser.parse("body[A0]")
        XCTAssertEqual(range.region, .body)
        XCTAssertEqual(range.start, CellAddress(row: 0, col: 0))
        XCTAssertEqual(range.end, CellAddress(row: 0, col: 0))
    }

    func testLabelBandAddress() throws {
        let range = try RangeParser.parse("top_labels[B1:D2]")
        XCTAssertEqual(range.region, .topLabels)
        XCTAssertEqual(range.start, CellAddress(row: 1, col: 1))
        XCTAssertEqual(range.end, CellAddress(row: 2, col: 3))
    }

    func testColumnLabelRoundTrip() throws {
        XCTAssertEqual(RangeParser.columnLabel(from: 0), "A")
        XCTAssertEqual(RangeParser.columnLabel(from: 25), "Z")
        XCTAssertEqual(RangeParser.columnLabel(from: 26), "AA")
        XCTAssertEqual(try RangeParser.columnIndex(from: "AA"), 26)
    }
}
