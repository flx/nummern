import SwiftUI
import Charts

/// Renders a chart from computed table values (line / bar / pie). Because the
/// data is read from the latest engine snapshot, charts update on every run.
struct ChartView: View {
    let chart: ChartSnapshot
    let table: TableSnapshot?

    var body: some View {
        VStack(spacing: 4) {
            if !chart.title.isEmpty {
                Text(chart.title).font(.caption).bold()
            }
            content
        }
        .padding(8)
    }

    @ViewBuilder
    private var content: some View {
        if let table {
            let series = ChartData.series(chart: chart, table: table)
            if series.allSatisfy({ $0.points.isEmpty }) {
                placeholder("No data")
            } else {
                switch chart.chart_type {
                case "pie": pie(series)
                case "bar": bars(series)
                default: lines(series)
                }
            }
        } else {
            placeholder("No data")
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lines(_ series: [ChartData.Series]) -> some View {
        Chart {
            ForEach(series) { s in
                ForEach(s.points) { p in
                    LineMark(x: .value("Category", p.category), y: .value("Value", p.value))
                        .foregroundStyle(by: .value("Series", s.name))
                }
            }
        }
        .chartLegend(chart.show_legend ? .visible : .hidden)
    }

    private func bars(_ series: [ChartData.Series]) -> some View {
        Chart {
            ForEach(series) { s in
                ForEach(s.points) { p in
                    BarMark(x: .value("Category", p.category), y: .value("Value", p.value))
                        .foregroundStyle(by: .value("Series", s.name))
                        .position(by: .value("Series", s.name))
                }
            }
        }
        .chartLegend(chart.show_legend ? .visible : .hidden)
    }

    private func pie(_ series: [ChartData.Series]) -> some View {
        let slices = series.first?.points ?? []
        return Chart(slices) { p in
            SectorMark(angle: .value("Value", p.value), innerRadius: .ratio(0.5))
                .foregroundStyle(by: .value("Category", p.category))
        }
        .chartLegend(chart.show_legend ? .visible : .hidden)
    }
}
