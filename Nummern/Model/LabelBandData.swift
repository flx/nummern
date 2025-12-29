import Foundation

enum LabelBandPosition: String, Codable, Equatable, Hashable {
    case top
    case bottom
    case left
    case right
}

struct LabelBandData: Codable, Equatable, Hashable {
    var top: [Int: [String]]
    var bottom: [Int: [String]]
    var left: [Int: [String]]
    var right: [Int: [String]]

    init(top: [Int: [String]] = [:],
         bottom: [Int: [String]] = [:],
         left: [Int: [String]] = [:],
         right: [Int: [String]] = [:]) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    mutating func set(band: LabelBandPosition, index: Int, values: [String]) {
        switch band {
        case .top:
            top[index] = values
        case .bottom:
            bottom[index] = values
        case .left:
            left[index] = values
        case .right:
            right[index] = values
        }
    }
}
