import Foundation

struct LabelBands: Codable, Equatable, Hashable {
    var topRows: Int
    var bottomRows: Int
    var leftCols: Int
    var rightCols: Int

    init(topRows: Int, bottomRows: Int, leftCols: Int, rightCols: Int) {
        self.topRows = topRows
        self.bottomRows = bottomRows
        self.leftCols = leftCols
        self.rightCols = rightCols
    }

    static let zero = LabelBands(topRows: 0, bottomRows: 0, leftCols: 0, rightCols: 0)
}
