import XCTest
@testable import Nummern

final class ChartTests: XCTestCase {
    /// A 4-row table: col A = Month (string), cols B/C = numeric series, with a
    /// top header row ["Month","Sales","Costs"].
    private func sampleTable() throws -> TableSnapshot {
        let json = """
        {"id":"t1","name":"t1","rect":{"x":0,"y":0,"w":1,"h":1},
         "grid":{"rows":3,"cols":3,"labels":{"top":1,"left":0,"bottom":0,"right":0}},
         "columns":[{"index":0,"name":"Month","dtype":"string","format":null},
                    {"index":1,"name":"Sales","dtype":"number","format":null},
                    {"index":2,"name":"Costs","dtype":"number","format":null}],
         "body":[["Jan","Feb","Mar"],[10,20,30],[4,5,6]],
         "labels":{"top":[["Month","Sales","Costs"]],"left":[],"bottom":[],"right":[]}}
        """
        return try JSONDecoder().decode(TableSnapshot.self, from: Data(json.utf8))
    }

    // MARK: derivation

    func testChartRangesSplitCategoryAndValues() {
        let rect = SelectionDerivation.Rect(r0: 0, c0: 0, r1: 2, c1: 2)
        let ranges = SelectionDerivation.chartRanges(rect)
        XCTAssertEqual(ranges.label, "A0:A2")     // first column = categories
        XCTAssertEqual(ranges.value, "B0:C2")     // remaining = value series
    }

    func testChartRangesSingleColumn() {
        let rect = SelectionDerivation.Rect(r0: 0, c0: 1, r1: 2, c1: 1)
        let ranges = SelectionDerivation.chartRanges(rect)
        XCTAssertNil(ranges.label)
        XCTAssertEqual(ranges.value, "B0:B2")
    }

    func testSummarySpecPicksNumericColumns() throws {
        let table = try sampleTable()
        let spec = SelectionDerivation.summarySpec(SelectionDerivation.bodyRect(table),
                                                   table: table, scoped: false)
        XCTAssertEqual(spec.groupBy, ["A"])
        XCTAssertEqual(spec.values.map(\.col), ["B", "C"])
        XCTAssertTrue(spec.values.allSatisfy { $0.agg == "sum" })
        XCTAssertNil(spec.sourceRange)
    }

    func testSummarySpecScopedRange() throws {
        let table = try sampleTable()
        let rect = SelectionDerivation.Rect(r0: 0, c0: 0, r1: 1, c1: 1)
        let spec = SelectionDerivation.summarySpec(rect, table: table, scoped: true)
        XCTAssertEqual(spec.sourceRange, "body[A0:B1]")
    }

    // MARK: chart data

    func testChartDataSeriesFromSnapshot() throws {
        let table = try sampleTable()
        let chart = try chartSnapshot(value: "B0:C2", label: "A0:A2", type: "bar")
        let series = ChartData.series(chart: chart, table: table)
        XCTAssertEqual(series.map(\.name), ["Sales", "Costs"])   // names from header row
        XCTAssertEqual(series[0].points.map(\.value), [10, 20, 30])
        XCTAssertEqual(series[0].points.map(\.category), ["Jan", "Feb", "Mar"])
    }

    // MARK: command serialization

    func testCommandSerialization() {
        XCTAssertEqual(
            AddChartCommand(sheetId: "sheet_1", id: "chart_1", chartType: "line",
                            tableId: "table_1", valueRange: "B0:C2", labelRange: "A0:A2",
                            title: "Trend").toPython(),
            #"chart_1 = proj.add_chart(sheet_1, "line", "table_1", value_range="B0:C2", label_range="A0:A2", title="Trend", id="chart_1")"#)

        XCTAssertEqual(
            SetChartSpecCommand(chartId: "chart_1", chartType: "bar", title: "X",
                                showLegend: false, valueRange: nil, labelRange: nil).toPython(),
            #"chart_1.set_spec(chart_type="bar", title="X", show_legend=False)"#)

        XCTAssertEqual(
            SetChartPositionCommand(chartId: "chart_1", x: 200, y: 120).toPython(),
            "chart_1.set_position(x=200, y=120)")

        XCTAssertEqual(
            AddSummaryCommand(sheetId: "sheet_1", id: "table_2", sourceId: "table_1",
                              groupBy: ["A"], values: [("B", "sum"), ("C", "sum")]).toPython(),
            #"table_2 = proj.add_summary(sheet_1, "table_1", group_by=["A"], values={"B": "sum", "C": "sum"}, id="table_2")"#)
    }

    private func chartSnapshot(value: String, label: String?, type: String) throws -> ChartSnapshot {
        let labelJSON = label.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"id":"chart_1","name":"chart_1","chart_type":"\(type)","table_id":"t1",
         "value_range":"\(value)","label_range":\(labelJSON),"title":"",
         "x_axis_title":"","y_axis_title":"","show_legend":true,
         "rect":{"x":0,"y":0,"w":360,"h":240}}
        """
        return try JSONDecoder().decode(ChartSnapshot.self, from: Data(json.utf8))
    }
}
