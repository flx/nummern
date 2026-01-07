import Foundation

enum ChartType: String, Codable, CaseIterable {
    case line
    case bar
    case pie

    var displayName: String {
        switch self {
        case .line:
            return "Line"
        case .bar:
            return "Bar"
        case .pie:
            return "Pie"
        }
    }
}

struct ChartModel: CanvasObject, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var rect: Rect
    var chartType: ChartType
    var tableId: String
    var valueRange: String
    var labelRange: String?
    var title: String
    var xAxisTitle: String
    var yAxisTitle: String
    var showLegend: Bool

    init(id: String,
         name: String,
         rect: Rect,
         chartType: ChartType,
         tableId: String,
         valueRange: String,
         labelRange: String? = nil,
         title: String = "",
         xAxisTitle: String = "",
         yAxisTitle: String = "",
         showLegend: Bool = true) {
        self.id = id
        self.name = name
        self.rect = rect
        self.chartType = chartType
        self.tableId = tableId
        self.valueRange = valueRange
        self.labelRange = labelRange
        self.title = title
        self.xAxisTitle = xAxisTitle
        self.yAxisTitle = yAxisTitle
        self.showLegend = showLegend
    }
}

struct SheetModel: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var tables: [TableModel]
    var charts: [ChartModel]

    init(id: String, name: String, tables: [TableModel] = [], charts: [ChartModel] = []) {
        self.id = id
        self.name = name
        self.tables = tables
        self.charts = charts
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case tables
        case charts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        tables = try container.decodeIfPresent([TableModel].self, forKey: .tables) ?? []
        charts = try container.decodeIfPresent([ChartModel].self, forKey: .charts) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(tables, forKey: .tables)
        try container.encode(charts, forKey: .charts)
    }
}
