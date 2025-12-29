import Foundation

enum ModelID {
    static func make() -> String {
        UUID().uuidString
    }
}
