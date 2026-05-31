import SwiftUI

/// Renders one table on the canvas: a title bar plus the virtualized AppKit grid
/// (label bands + body).
struct TableFrameView: View {
    let table: TableSnapshot
    let isSelected: Bool
    var selectedCell: (row: Int, col: Int)? = nil
    var onSelectCell: ((Int, Int) -> Void)? = nil
    var onNavigate: ((KeyboardNavigator.Key) -> Void)? = nil
    var onClear: (() -> Void)? = nil
    var onEscape: (() -> Void)? = nil

    private var gridSize: CGSize { GridGeometry.size(table) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            TableGridView(table: table, selectedCell: selectedCell, onSelectCell: onSelectCell,
                          onNavigate: onNavigate, onClear: onClear, onEscape: onEscape)
                .frame(width: gridSize.width, height: gridSize.height)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.4),
                        lineWidth: isSelected ? 2 : 1)
        )
        .cornerRadius(4)
        .shadow(radius: isSelected ? 4 : 1)
    }

    private var titleBar: some View {
        Text(table.name)
            .font(.caption).bold()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.12))
    }
}
