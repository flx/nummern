import Foundation

enum SummaryAggregation: String, Codable, CaseIterable {
    case sum
    case avg
    case min
    case max
    case count

    var displayName: String {
        switch self {
        case .sum:
            return "Sum"
        case .avg:
            return "Average"
        case .min:
            return "Min"
        case .max:
            return "Max"
        case .count:
            return "Count"
        }
    }
}

struct SummaryValueSpec: Codable, Equatable, Hashable {
    let column: Int
    let aggregation: SummaryAggregation

    private enum CodingKeys: String, CodingKey {
        case column = "col"
        case aggregation = "agg"
    }
}

struct SummarySpec: Codable, Equatable, Hashable {
    let sourceTableId: String
    let sourceRange: String?
    let groupBy: [Int]
    let values: [SummaryValueSpec]
}

struct TableModel: CanvasObject, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var rect: Rect
    var gridSpec: GridSpec
    var bodyColumnTypes: [ColumnDataType]
    var cellValues: [String: CellValue]
    var rangeValues: [String: RangeValue]
    var formulas: [String: FormulaSpec]
    var labelBandValues: LabelBandData
    var summarySpec: SummarySpec?

    init(id: String,
         name: String,
         rect: Rect,
         rows: Int = 10,
         cols: Int = 6,
         labelBands: LabelBands = .zero,
         bodyColumnTypes: [ColumnDataType] = [],
         cellValues: [String: CellValue] = [:],
         rangeValues: [String: RangeValue] = [:],
         formulas: [String: FormulaSpec] = [:],
         labelBandValues: LabelBandData = LabelBandData(),
         summarySpec: SummarySpec? = nil) {
        self.id = id
        self.name = name
        self.rect = rect
        self.gridSpec = GridSpec(bodyRows: rows, bodyCols: cols, labelBands: labelBands)
        if bodyColumnTypes.isEmpty {
            self.bodyColumnTypes = Array(repeating: .number, count: cols)
        } else {
            self.bodyColumnTypes = bodyColumnTypes
        }
        self.cellValues = cellValues
        self.rangeValues = rangeValues
        self.formulas = formulas
        self.labelBandValues = labelBandValues
        self.summarySpec = summarySpec
        normalizeColumnTypes()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case rect
        case gridSpec
        case bodyColumnTypes
        case cellValues
        case rangeValues
        case formulas
        case labelBandValues
        case summarySpec
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        rect = try container.decode(Rect.self, forKey: .rect)
        gridSpec = try container.decode(GridSpec.self, forKey: .gridSpec)
        bodyColumnTypes = (try? container.decode([ColumnDataType].self, forKey: .bodyColumnTypes)) ?? []
        cellValues = try container.decodeIfPresent([String: CellValue].self, forKey: .cellValues) ?? [:]
        rangeValues = try container.decodeIfPresent([String: RangeValue].self, forKey: .rangeValues) ?? [:]
        formulas = try container.decodeIfPresent([String: FormulaSpec].self, forKey: .formulas) ?? [:]
        labelBandValues = try container.decodeIfPresent(LabelBandData.self, forKey: .labelBandValues) ?? LabelBandData()
        summarySpec = try container.decodeIfPresent(SummarySpec.self, forKey: .summarySpec)
        if bodyColumnTypes.isEmpty {
            bodyColumnTypes = Array(repeating: .number, count: gridSpec.bodyCols)
        }
        normalizeColumnTypes()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(rect, forKey: .rect)
        try container.encode(gridSpec, forKey: .gridSpec)
        try container.encode(bodyColumnTypes, forKey: .bodyColumnTypes)
        try container.encode(cellValues, forKey: .cellValues)
        try container.encode(rangeValues, forKey: .rangeValues)
        try container.encode(formulas, forKey: .formulas)
        try container.encode(labelBandValues, forKey: .labelBandValues)
        try container.encode(summarySpec, forKey: .summarySpec)
    }

    mutating func normalizeColumnTypes() {
        let target = gridSpec.bodyCols
        if bodyColumnTypes.count < target {
            let missing = target - bodyColumnTypes.count
            bodyColumnTypes.append(contentsOf: Array(repeating: .number, count: missing))
        } else if bodyColumnTypes.count > target {
            bodyColumnTypes = Array(bodyColumnTypes.prefix(target))
        }
    }

    mutating func updateColumnType(forBodyColumn col: Int, value: CellValue) {
        guard col >= 0 else {
            return
        }
        if bodyColumnTypes.count <= col {
            let missing = col - bodyColumnTypes.count + 1
            bodyColumnTypes.append(contentsOf: Array(repeating: .number, count: missing))
        }
        let currentType = bodyColumnTypes[col]
        guard currentType == .number || currentType == .string else {
            return
        }
        switch value {
        case .string:
            bodyColumnTypes[col] = .string
        case .number, .bool, .date, .time:
            if currentType != .string {
                bodyColumnTypes[col] = .number
            }
        case .empty:
            break
        }
    }
}

extension TableModel {
    func bodyContentBounds() -> (maxRow: Int, maxCol: Int)? {
        var maxRow: Int?
        var maxCol: Int?

        func consider(_ range: RangeAddress) {
            guard range.region == .body else {
                return
            }
            let row = max(range.start.row, range.end.row)
            let col = max(range.start.col, range.end.col)
            maxRow = maxRow.map { max($0, row) } ?? row
            maxCol = maxCol.map { max($0, col) } ?? col
        }

        for (key, value) in cellValues {
            guard value != .empty,
                  let range = try? RangeParser.parse(key) else {
                continue
            }
            consider(range)
        }

        for (key, formula) in formulas {
            let trimmed = formula.formula.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let range = try? RangeParser.parse(key) else {
                continue
            }
            consider(range)
        }

        guard let maxRow, let maxCol else {
            return nil
        }
        return (maxRow, maxCol)
    }
}
