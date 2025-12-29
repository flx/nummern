import Foundation

struct Rect: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    static let zero = Rect(x: 0, y: 0, width: 0, height: 0)
}
