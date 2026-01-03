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
}
