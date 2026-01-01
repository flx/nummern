import XCTest
@testable import Nummern

final class PythonLogNormalizerTests: XCTestCase {
    func testMergesConsecutiveFormulaContextBlocks() {
        let raw = """
t = proj.table('table_1')
with formula_context(t):
    a1 = 1
t = proj.table('table_1')
with formula_context(t):
    a2 = 2
t = proj.table('table_1')
with formula_context(t):
    b3 = 3
t = proj.table('table_1')
with formula_context(t):
    b2 = a1+a2+b3
"""

        let expected = """
t = proj.table('table_1')
with formula_context(t):
    a1 = 1
    a2 = 2
    b3 = 3
    b2 = a1+a2+b3
"""

        XCTAssertEqual(PythonLogNormalizer.normalize(raw), expected)
    }
}
