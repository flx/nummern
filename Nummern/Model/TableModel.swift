import Foundation

struct TableModel: CanvasObject, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var rect: Rect
    var gridSpec: GridSpec
    var cellValues: [String: CellValue]
    var rangeValues: [String: RangeValue]
    var formulas: [String: FormulaSpec]
    var labelBandValues: LabelBandData

    init(id: String = ModelID.make(),
         name: String,
         rect: Rect,
         rows: Int = 10,
         cols: Int = 6,
         labelBands: LabelBands = .zero,
         cellValues: [String: CellValue] = [:],
         rangeValues: [String: RangeValue] = [:],
         formulas: [String: FormulaSpec] = [:],
         labelBandValues: LabelBandData = LabelBandData()) {
        self.id = id
        self.name = name
        self.rect = rect
        self.gridSpec = GridSpec(bodyRows: rows, bodyCols: cols, labelBands: labelBands)
        self.cellValues = cellValues
        self.rangeValues = rangeValues
        self.formulas = formulas
        self.labelBandValues = labelBandValues
    }
}
