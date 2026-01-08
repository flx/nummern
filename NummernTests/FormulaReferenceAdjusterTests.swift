import XCTest
@testable import Nummern

final class FormulaReferenceAdjusterTests: XCTestCase {
    func testAdjustsRelativeReferences() {
        let result = FormulaReferenceAdjuster.adjust("=c_sin(A1)", rowDelta: 1, colDelta: 0)
        XCTAssertEqual(result, "=c_sin(A2)")
    }

    func testPreservesAbsoluteMarkers() {
        let result = FormulaReferenceAdjuster.adjust("=A1+$B2+$C$3", rowDelta: 1, colDelta: 2)
        XCTAssertEqual(result, "=C2+$B3+$C$3")
    }

    func testSkipsTableQualifiedReferences() {
        let result = FormulaReferenceAdjuster.adjust("=table_1.A1+B1", rowDelta: 1, colDelta: 0)
        XCTAssertEqual(result, "=table_1.A1+B2")
    }

    func testAdjustsRangeReferences() {
        let result = FormulaReferenceAdjuster.adjust("=SUM(A0:B1)", rowDelta: 1, colDelta: 1)
        XCTAssertEqual(result, "=SUM(B1:C2)")
    }
}
