import XCTest
@testable import Nummern

final class ProjectPersistenceTests: XCTestCase {
    func testEncodeDecodeProjectJson() throws {
        let table = TableModel(
            id: "table_1",
            name: "Table 1",
            rect: Rect(x: 10, y: 20, width: 300, height: 200),
            rows: 12,
            cols: 4,
            labelBands: LabelBands(topRows: 1, bottomRows: 0, leftCols: 1, rightCols: 0)
        )
        let sheet = SheetModel(id: "sheet_1", name: "Sheet 1", tables: [table])
        let project = ProjectModel(sheets: [sheet])

        let file = ProjectFileStore.make(project: project)
        let data = try ProjectFileStore.encode(file)
        let decoded = try ProjectFileStore.decode(data)

        XCTAssertEqual(decoded.schemaVersion, ProjectFileStore.schemaVersion)
        XCTAssertEqual(decoded.project, project)
    }

    func testPackageLayout() throws {
        let table = TableModel(
            id: "table_1",
            name: "Table 1",
            rect: Rect(x: 0, y: 0, width: 100, height: 80)
        )
        let sheet = SheetModel(id: "sheet_1", name: "Sheet 1", tables: [table])
        let project = ProjectModel(sheets: [sheet])
        let document = NummernDocument(project: project, script: "print('hi')", historyJSON: "{\"commands\": []}")

        let wrapper = try document.makeFileWrapper()
        XCTAssertTrue(wrapper.isDirectory)

        let children = wrapper.fileWrappers ?? [:]
        XCTAssertNotNil(children["project.json"])
        XCTAssertNotNil(children["script.py"])
        XCTAssertNotNil(children["history.json"])

        let projectData = try XCTUnwrap(children["project.json"]?.regularFileContents)
        let decoded = try ProjectFileStore.decode(projectData)
        XCTAssertEqual(decoded.project, project)

        let scriptData = try XCTUnwrap(children["script.py"]?.regularFileContents)
        XCTAssertEqual(String(data: scriptData, encoding: .utf8), "print('hi')")
    }
}
