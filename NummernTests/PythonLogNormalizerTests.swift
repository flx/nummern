import XCTest
@testable import Nummern

final class PythonLogNormalizerTests: XCTestCase {
    func testMovesDataBlocksAfterAddTable() {
        let raw = """
proj.add_table('sheet_1', table_id='table_1', name='table_1', x=0, y=0, rows=2, cols=2, labels=dict(top=0, left=0, bottom=0, right=0))
t = proj.table('table_1')
with table_context(t):
    a1 = 1
t = proj.table('table_1')
with table_context(t):
    a2 = 2
t = proj.table('table_1')
with table_context(t):
    b3 = 3
t = proj.table('table_1')
with table_context(t):
    b2 = a1+a2+b3
"""

        let expected = """
table_1 = proj.add_table('sheet_1', table_id='table_1', name='table_1', x=0, y=0, rows=2, cols=2, labels=dict(top=0, left=0, bottom=0, right=0))
with table_context(table_1):
    a1 = 1
    a2 = 2
    b3 = 3
with table_context(table_1):
    b2 = a1+a2+b3
"""

        XCTAssertEqual(PythonLogNormalizer.normalize(raw), expected)
    }

    func testHoistsQuotedSetRangeIntoDataBlock() {
        let raw = """
proj.add_table('sheet_1', table_id='table_1', name='table_1', x=0, y=0, rows=2, cols=2, labels=dict(top=0, left=0, bottom=0, right=0))
proj.table('table_1').set_range('body[A0:B1]', [[1, 2], [3, 4]])
"""

        let expected = """
table_1 = proj.add_table('sheet_1', table_id='table_1', name='table_1', x=0, y=0, rows=2, cols=2, labels=dict(top=0, left=0, bottom=0, right=0))
with table_context(table_1):
    proj.table('table_1').set_range('body[A0:B1]', [[1, 2], [3, 4]])
"""

        XCTAssertEqual(PythonLogNormalizer.normalize(raw), expected)
    }

    func testPreservesAddTableAssignmentBeforeContext() {
        let raw = """
table_1 = proj.add_table('sheet_1', table_id='table_1', name='table_1', x=0, y=0, rows=2, cols=2, labels=dict(top=0, left=0, bottom=0, right=0))
t = proj.table('table_1')
with table_context(t):
    a0 = 1
"""

        let expected = """
table_1 = proj.add_table('sheet_1', table_id='table_1', name='table_1', x=0, y=0, rows=2, cols=2, labels=dict(top=0, left=0, bottom=0, right=0))
with table_context(table_1):
    a0 = 1
"""

        XCTAssertEqual(PythonLogNormalizer.normalize(raw), expected)
    }
}
