import XCTest
@testable import Nummern

final class TableNamingTests: XCTestCase {
    func testTableNameDefaultsToId() {
        let viewModel = CanvasViewModel()
        let sheet = viewModel.addSheet()
        let table = viewModel.addTable(toSheetId: sheet.id)

        let created = try? XCTUnwrap(table)
        XCTAssertEqual(created?.name, created?.id)
    }
}
