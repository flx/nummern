import SwiftUI

/// Renders one table on the canvas: its label bands and body as a simple grid.
/// (S3 replaces the inner grid with a virtualized AppKit renderer.)
struct TableFrameView: View {
    let table: TableSnapshot
    let isSelected: Bool
    var selectedCell: (row: Int, col: Int)? = nil
    var onSelectCell: ((Int, Int) -> Void)? = nil

    private var totalCols: Int { GridGeometry.totalCols(table) }
    private var totalRows: Int { GridGeometry.totalRows(table) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            grid
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

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<max(totalRows, 0), id: \.self) { gr in
                HStack(spacing: 0) {
                    ForEach(0..<max(totalCols, 0), id: \.self) { gc in
                        cellView(GridGeometry.cell(table, gr: gr, gc: gc))
                    }
                }
            }
        }
    }

    private func cellView(_ info: GridGeometry.CellInfo) -> some View {
        let isLabel = info.region != .body && info.region != .corner
        let isSelectedCell = info.region == .body
            && selectedCell?.row == info.row && selectedCell?.col == info.col
        return Text(info.value.displayText())
            .font(.system(size: 11, design: isLabel ? .default : .monospaced))
            .fontWeight(isLabel ? .semibold : .regular)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: GridGeometry.cellWidth, height: GridGeometry.cellHeight, alignment: alignment(info))
            .padding(.horizontal, 3)
            .frame(width: GridGeometry.cellWidth, height: GridGeometry.cellHeight)
            .background(background(info.region))
            .overlay(Rectangle().stroke(isSelectedCell ? Color.accentColor : Color.gray.opacity(0.18),
                                        lineWidth: isSelectedCell ? 1.5 : 0.5))
            .contentShape(Rectangle())
            .onTapGesture {
                if info.region == .body { onSelectCell?(info.row, info.col) }
            }
    }

    private func alignment(_ info: GridGeometry.CellInfo) -> Alignment {
        if case .number = info.value { return .trailing }
        return .leading
    }

    private func background(_ region: GridGeometry.Region) -> Color {
        switch region {
        case .body: return Color(nsColor: .textBackgroundColor)
        case .corner: return Color.gray.opacity(0.06)
        default: return Color.gray.opacity(0.10)
        }
    }
}
