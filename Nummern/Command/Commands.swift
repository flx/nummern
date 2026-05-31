import Foundation

// The small, explicit command set. Each emits one statement of plain Python.
// Object ids are used directly as variable names in the script.

struct AddSheetCommand: Command {
    let id: String
    let name: String
    func toPython() -> String {
        "\(id) = proj.add_sheet(\(PythonLiteralEncoder.string(name)), id=\(PythonLiteralEncoder.string(id)))"
    }
}

struct AddTableCommand: Command {
    let sheetId: String
    let id: String
    let x: Double
    let y: Double
    let rows: Int
    let cols: Int
    let labels: LabelBandsDTO
    func toPython() -> String {
        "\(id) = proj.add_table(\(sheetId), id=\(PythonLiteralEncoder.string(id)), "
        + "x=\(PythonLiteralEncoder.number(x)), y=\(PythonLiteralEncoder.number(y)), "
        + "rows=\(rows), cols=\(cols), labels=\(PythonLiteralEncoder.labelsKwarg(labels)))"
    }
}

struct SetPositionCommand: Command {
    let tableId: String
    let x: Double
    let y: Double
    func toPython() -> String {
        "\(tableId).set_position(x=\(PythonLiteralEncoder.number(x)), y=\(PythonLiteralEncoder.number(y)))"
    }
}

struct ResizeCommand: Command {
    let tableId: String
    let rows: Int
    let cols: Int
    func toPython() -> String {
        "\(tableId).resize(rows=\(rows), cols=\(cols))"
    }
}

struct MinimizeCommand: Command {
    let tableId: String
    func toPython() -> String { "\(tableId).minimize()" }
}

struct SetLabelBandCommand: Command {
    let tableId: String
    let region: String   // "top" / "left" / "bottom" / "right"
    let values: [String] // single row/col fill
    func toPython() -> String {
        "\(tableId).\(region)[:] = \(PythonLiteralEncoder.stringList(values))"
    }
}

/// A literal value block: `t["A0:B1"] = [[...]]`.
struct SetLiteralCommand: Command {
    let tableId: String
    let range: String
    let values: [[CellValue]]
    func toPython() -> String {
        "\(tableId)[\(PythonLiteralEncoder.string(range))] = \(PythonLiteralEncoder.grid(values))"
    }
}

/// A derived value — "a formula" — which is just a Python expression:
/// `t["F"] = t["B"] + t["C"]`. `expr` is verbatim Python referencing table vars.
struct SetExprCommand: Command {
    let tableId: String
    let target: String
    let expr: String
    func toPython() -> String {
        "\(tableId)[\(PythonLiteralEncoder.string(target))] = \(expr)"
    }
}

struct ClearRangeCommand: Command {
    let tableId: String
    let range: String
    func toPython() -> String {
        // pandas-native clear: assign None across the range
        "\(tableId)[\(PythonLiteralEncoder.string(range))] = None"
    }
}

struct SetColumnTypeCommand: Command {
    let tableId: String
    let col: Int
    let type: String
    func toPython() -> String {
        "\(tableId).set_column_type(\(col), \(PythonLiteralEncoder.string(type)))"
    }
}

struct AddSummaryCommand: Command {
    let sheetId: String
    let id: String
    let sourceId: String
    let groupBy: [String]
    let values: [(col: String, agg: String)]
    func toPython() -> String {
        let group = PythonLiteralEncoder.stringList(groupBy)
        let vals = "{" + values.map {
            "\(PythonLiteralEncoder.string($0.col)): \(PythonLiteralEncoder.string($0.agg))"
        }.joined(separator: ", ") + "}"
        return "\(id) = proj.add_summary(\(sheetId), \(PythonLiteralEncoder.string(sourceId)), "
            + "group_by=\(group), values=\(vals), id=\(PythonLiteralEncoder.string(id)))"
    }
}

struct SetChartPositionCommand: Command {
    let chartId: String
    let x: Double
    let y: Double
    func toPython() -> String {
        "\(chartId).set_position(x=\(PythonLiteralEncoder.number(x)), y=\(PythonLiteralEncoder.number(y)))"
    }
}

struct SetChartSpecCommand: Command {
    let chartId: String
    var chartType: String?
    var title: String?
    var showLegend: Bool?
    var valueRange: String?
    var labelRange: String?
    func toPython() -> String {
        var parts: [String] = []
        if let chartType { parts.append("chart_type=\(PythonLiteralEncoder.string(chartType))") }
        if let valueRange { parts.append("value_range=\(PythonLiteralEncoder.string(valueRange))") }
        if let labelRange { parts.append("label_range=\(PythonLiteralEncoder.string(labelRange))") }
        if let title { parts.append("title=\(PythonLiteralEncoder.string(title))") }
        if let showLegend { parts.append("show_legend=\(showLegend ? "True" : "False")") }
        return "\(chartId).set_spec(" + parts.joined(separator: ", ") + ")"
    }
}

struct AddChartCommand: Command {
    let sheetId: String
    let id: String
    let chartType: String
    let tableId: String
    let valueRange: String
    let labelRange: String?
    let title: String
    func toPython() -> String {
        var parts = ["\(sheetId)", PythonLiteralEncoder.string(chartType),
                     PythonLiteralEncoder.string(tableId)]
        parts.append("value_range=\(PythonLiteralEncoder.string(valueRange))")
        if let labelRange { parts.append("label_range=\(PythonLiteralEncoder.string(labelRange))") }
        if !title.isEmpty { parts.append("title=\(PythonLiteralEncoder.string(title))") }
        parts.append("id=\(PythonLiteralEncoder.string(id))")
        return "\(id) = proj.add_chart(" + parts.joined(separator: ", ") + ")"
    }
}
