import XCTest
@testable import Nummern

final class PythonErrorParserTests: XCTestCase {
    func testParsesTracebackLineAndMessage() {
        let stderr = """
Traceback (most recent call last):
  File "/tmp/num_script.py", line 12, in <module>
    result = 1 / 0
ZeroDivisionError: division by zero
"""
        let detail = PythonErrorParser.parse(stderr: stderr)
        XCTAssertEqual(detail.line, 12)
        XCTAssertEqual(detail.message, "ZeroDivisionError: division by zero")
    }

    func testParsesRunnerErrorMessage() {
        let stderr = "Error: name 'dict' is not defined\n"
        let detail = PythonErrorParser.parse(stderr: stderr)
        XCTAssertNil(detail.line)
        XCTAssertEqual(detail.message, "name 'dict' is not defined")
    }
}
