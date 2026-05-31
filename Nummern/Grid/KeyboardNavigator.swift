import Foundation

/// Pure cell-navigation logic for keyboard interaction (README §5.10.8).
/// Movement is clamped to the body grid.
enum KeyboardNavigator {
    enum Key { case up, down, left, right, enter, tab, backTab }

    static func move(from cell: (row: Int, col: Int), key: Key,
                     rows: Int, cols: Int) -> (row: Int, col: Int) {
        var (r, c) = cell
        switch key {
        case .up: r -= 1
        case .down, .enter: r += 1
        case .left, .backTab: c -= 1
        case .right, .tab: c += 1
        }
        return (clamp(r, 0, rows - 1), clamp(c, 0, cols - 1))
    }

    private static func clamp(_ value: Int, _ lo: Int, _ hi: Int) -> Int {
        guard hi >= lo else { return lo }
        return min(max(value, lo), hi)
    }
}
