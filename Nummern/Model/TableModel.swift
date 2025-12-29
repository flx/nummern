import Foundation

struct TableModel: CanvasObject, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var rect: Rect
    var gridSpec: GridSpec

    init(id: String = ModelID.make(),
         name: String,
         rect: Rect,
         rows: Int = 10,
         cols: Int = 6,
         labelBands: LabelBands = .zero) {
        self.id = id
        self.name = name
        self.rect = rect
        self.gridSpec = GridSpec(bodyRows: rows, bodyCols: cols, labelBands: labelBands)
    }
}
