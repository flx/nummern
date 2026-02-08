import XCTest
@testable import Nummern

final class CommandSerializationTests: XCTestCase {
    func testPythonOutputDeterminism() {
        let mapA: [String: CellValue] = [
            "body[B0]": .number(2),
            "body[A0]": .number(1)
        ]
        let mapB: [String: CellValue] = [
            "body[A0]": .number(1),
            "body[B0]": .number(2)
        ]

        let commandA = SetCellsCommand(tableId: "table_1", cellMap: mapA)
        let commandB = SetCellsCommand(tableId: "table_1", cellMap: mapB)

        XCTAssertEqual(commandA.serializeToPython(), commandB.serializeToPython())
    }

    func testColumnTypeSerialization() {
        let command = SetColumnTypeCommand(tableId: "table_1", col: 2, columnType: .percentage)

        XCTAssertEqual(command.serializeToPython(),
                       "proj.table('table_1').set_column_type(col=2, type='percentage')")
    }

    func testAddChartSerialization() {
        let rect = Rect(x: 10, y: 20, width: 300, height: 200)
        let command = AddChartCommand(sheetId: "sheet_1",
                                      chartId: "chart_1",
                                      name: "chart_1",
                                      rect: rect,
                                      chartType: .line,
                                      tableId: "table_1",
                                      valueRange: "body[A0:A4]",
                                      labelRange: nil,
                                      title: "",
                                      xAxisTitle: "",
                                      yAxisTitle: "",
                                      showLegend: true)

        XCTAssertEqual(command.serializeToPython(),
                       "proj.add_chart('sheet_1', chart_id='chart_1', name='chart_1', chart_type='line', table_id='table_1', value_range='body[A0:A4]', label_range=None, x=10, y=20, width=300, height=200, title='', x_axis_title='', y_axis_title='', show_legend=True)")
    }

    func testUpdateChartSerialization() {
        let command = UpdateChartCommand(chartId: "chart_1",
                                         chartType: .bar,
                                         valueRange: "body[A0:A3]",
                                         labelRange: .clear,
                                         title: "Sales",
                                         showLegend: false)

        XCTAssertEqual(command.serializeToPython(),
                       "proj.chart('chart_1').set_spec(chart_type='bar', value_range='body[A0:A3]', label_range=None, title='Sales', show_legend=False)")
    }

    func testSetRangeSerializationPadsRaggedRows() {
        let command = SetRangeCommand(tableId: "table_1",
                                      range: "body[A0:B1]",
                                      values: [[.number(1)], [.number(2), .number(3)]])

        XCTAssertEqual(command.serializeToPython(),
                       "proj.table('table_1').set_range('body[A0:B1]', [[1, None], [2, 3]])")
    }
}
