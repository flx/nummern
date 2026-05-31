import SwiftUI

/// Basic chart inspector: type, title, legend, and data ranges. Edits record a
/// `chart_id.set_spec(...)` command and re-run (README §5.9, §5.10.7).
struct ChartInspector: View {
    @ObservedObject var document: NummernDocument
    let chartId: String

    @State private var title = ""
    @State private var valueRange = ""
    @State private var labelRange = ""

    private var chart: ChartSnapshot? { document.chart(id: chartId) }

    var body: some View {
        Form {
            Section("Chart") {
                if let chart {
                    Picker("Type", selection: typeBinding(chart)) {
                        Text("Line").tag("line")
                        Text("Bar").tag("bar")
                        Text("Pie").tag("pie")
                    }
                    Toggle("Legend", isOn: legendBinding(chart))
                }
                TextField("Title", text: $title)
                    .onSubmit { document.setChartSpec(chartId, title: title) }
            }
            Section("Data") {
                TextField("Values", text: $valueRange)
                    .onSubmit { document.setChartSpec(chartId, valueRange: valueRange) }
                TextField("Categories", text: $labelRange)
                    .onSubmit { commitLabelRange() }
            }
        }
        .formStyle(.grouped)
        .onAppear { sync() }
        .onChange(of: chartId) { _, _ in sync() }
    }

    private func sync() {
        guard let chart else { return }
        title = chart.title
        valueRange = chart.value_range
        labelRange = chart.label_range ?? ""
    }

    private func commitLabelRange() {
        let trimmed = labelRange.trimmingCharacters(in: .whitespaces)
        document.setChartSpec(chartId, labelRange: trimmed.isEmpty ? nil : trimmed)
    }

    private func typeBinding(_ chart: ChartSnapshot) -> Binding<String> {
        Binding(get: { chart.chart_type },
                set: { document.setChartSpec(chartId, chartType: $0) })
    }

    private func legendBinding(_ chart: ChartSnapshot) -> Binding<Bool> {
        Binding(get: { chart.show_legend },
                set: { document.setChartSpec(chartId, showLegend: $0) })
    }
}
