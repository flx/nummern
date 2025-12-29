import XCTest
@testable import Nummern

final class ProjectModelTests: XCTestCase {
    func testStableIdsPersistOnRename() {
        let store = ProjectStore()
        let sheet = store.addSheet(name: "Sheet 1")
        let originalId = sheet.id

        store.renameSheet(id: originalId, to: "Renamed")

        XCTAssertEqual(store.project.sheets.count, 1)
        XCTAssertEqual(store.project.sheets.first?.id, originalId)
        XCTAssertEqual(store.project.sheets.first?.name, "Renamed")
    }
}
