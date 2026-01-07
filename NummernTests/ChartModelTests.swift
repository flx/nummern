import XCTest
@testable import Nummern

final class ChartModelTests: XCTestCase {
    func testSheetDecodeDefaultsChartsToEmpty() throws {
        let json = """
        {
          "id": "sheet_1",
          "name": "Sheet 1",
          "tables": []
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SheetModel.self, from: data)
        XCTAssertEqual(decoded.charts, [])
    }

    func testProjectEncodeDecodeWithChart() throws {
        let chart = ChartModel(id: "chart_1",
                               name: "chart_1",
                               rect: Rect(x: 12, y: 24, width: 320, height: 200),
                               chartType: .line,
                               tableId: "table_1",
                               valueRange: "body[A0:A3]",
                               labelRange: "body[B0:B3]",
                               title: "Sales",
                               xAxisTitle: "Month",
                               yAxisTitle: "Amount",
                               showLegend: true)
        let sheet = SheetModel(id: "sheet_1", name: "Sheet 1", charts: [chart])
        let project = ProjectModel(sheets: [sheet])

        let file = ProjectFileStore.make(project: project)
        let data = try ProjectFileStore.encode(file)
        let decoded = try ProjectFileStore.decode(data)

        XCTAssertEqual(decoded.project, project)
    }
}
