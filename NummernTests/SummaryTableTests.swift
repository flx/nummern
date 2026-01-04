import XCTest
@testable import Nummern

final class SummaryTableTests: XCTestCase {
    func testCreateSummaryTableCommandSerializes() {
        let command = CreateSummaryTableCommand(sheetId: "sheet_1",
                                                tableId: "summary_1",
                                                name: "summary_1",
                                                rect: Rect(x: 80, y: 80, width: 160, height: 24),
                                                sourceTableId: "table_1",
                                                groupBy: [0],
                                                values: [SummaryValueSpec(column: 1, aggregation: .sum)],
                                                rows: 1,
                                                cols: 2)

        let expected = "proj.add_summary_table('sheet_1', table_id='summary_1', name='summary_1', " +
        "source_table_id='table_1', group_by=['A'], values=[dict(col='B', agg='sum')], x=80, y=80)"
        XCTAssertEqual(command.serializeToPython(), expected)
    }

    func testCreateSummaryTableCommandAppliesSummarySpec() {
        var project = ProjectModel(sheets: [SheetModel(id: "sheet_1", name: "Sheet 1")])
        let command = CreateSummaryTableCommand(sheetId: "sheet_1",
                                                tableId: "summary_1",
                                                name: "summary_1",
                                                rect: Rect(x: 80, y: 80, width: 160, height: 24),
                                                sourceTableId: "table_1",
                                                groupBy: [0],
                                                values: [SummaryValueSpec(column: 1, aggregation: .sum)],
                                                rows: 1,
                                                cols: 2)

        command.apply(to: &project)
        let table = project.sheets[0].tables[0]
        XCTAssertEqual(table.summarySpec?.sourceTableId, "table_1")
        XCTAssertEqual(table.summarySpec?.groupBy, [0])
        XCTAssertEqual(table.summarySpec?.values, [SummaryValueSpec(column: 1, aggregation: .sum)])
        XCTAssertEqual(table.gridSpec.bodyRows, 1)
        XCTAssertEqual(table.gridSpec.bodyCols, 2)
        XCTAssertEqual(table.gridSpec.labelBands, .zero)
    }
}
