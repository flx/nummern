import Foundation

protocol CanvasObject {
    var id: String { get }
    var name: String { get set }
    var rect: Rect { get set }
}
