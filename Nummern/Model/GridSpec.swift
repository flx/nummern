import Foundation

struct GridSpec: Codable, Equatable, Hashable {
    var bodyRows: Int
    var bodyCols: Int
    var labelBands: LabelBands

    init(bodyRows: Int, bodyCols: Int, labelBands: LabelBands = .zero) {
        self.bodyRows = bodyRows
        self.bodyCols = bodyCols
        self.labelBands = labelBands
    }
}
