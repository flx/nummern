import SwiftUI

private enum CanvasCoordinateSpace {
    static let name = "canvas"
}

struct CanvasView: View {
    let sheet: SheetModel
    @ObservedObject var viewModel: CanvasViewModel

    private let canvasSize = CGSize(width: 2400, height: 1600)

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.clearSelection()
                    }

                ForEach(sheet.tables, id: \.id) { table in
                    TableCanvasItem(table: table, viewModel: viewModel)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .coordinateSpace(name: CanvasCoordinateSpace.name)
        }
    }
}

struct TableCanvasItem: View {
    let table: TableModel
    @ObservedObject var viewModel: CanvasViewModel

    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero
    @State private var isResizing = false

    private let minSize = CGSize(width: 140, height: 90)
    private let cellSize = CGSize(width: 80, height: 24)

    var body: some View {
        let width = max(Double(minSize.width), table.rect.width + Double(resizeDelta.width))
        let height = max(Double(minSize.height), table.rect.height + Double(resizeDelta.height))
        let originX = table.rect.x + Double(dragOffset.width)
        let originY = table.rect.y + Double(dragOffset.height)
        let centerX = originX + width / 2.0
        let centerY = originY + height / 2.0
        let metrics = TableGridMetrics(cellSize: cellSize,
                                       bodyRows: table.gridSpec.bodyRows,
                                       bodyCols: table.gridSpec.bodyCols,
                                       labelBands: table.gridSpec.labelBands)
        let selectedCell = viewModel.selectedCell?.tableId == table.id ? viewModel.selectedCell : nil

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary, lineWidth: 1)
                )

            ZStack(alignment: .topLeading) {
                if metrics.topRows > 0 {
                    TableGridView(rows: metrics.topRows,
                                  cols: metrics.bodyCols,
                                  cellSize: cellSize)
                        .frame(width: metrics.bodyWidth, height: metrics.topHeight, alignment: .topLeading)
                        .offset(x: metrics.leftWidth, y: 0)
                        .allowsHitTesting(false)
                }
                if metrics.leftCols > 0 {
                    TableGridView(rows: metrics.bodyRows,
                                  cols: metrics.leftCols,
                                  cellSize: cellSize)
                        .frame(width: metrics.leftWidth, height: metrics.bodyHeight, alignment: .topLeading)
                        .offset(x: 0, y: metrics.topHeight)
                        .allowsHitTesting(false)
                }
                TableGridView(rows: metrics.bodyRows,
                              cols: metrics.bodyCols,
                              cellSize: cellSize)
                    .frame(width: metrics.bodyWidth, height: metrics.bodyHeight, alignment: .topLeading)
                    .offset(x: metrics.leftWidth, y: metrics.topHeight)
                    .allowsHitTesting(false)
                if metrics.rightCols > 0 {
                    TableGridView(rows: metrics.bodyRows,
                                  cols: metrics.rightCols,
                                  cellSize: cellSize)
                        .frame(width: metrics.rightWidth, height: metrics.bodyHeight, alignment: .topLeading)
                        .offset(x: metrics.leftWidth + metrics.bodyWidth, y: metrics.topHeight)
                        .allowsHitTesting(false)
                }
                if metrics.bottomRows > 0 {
                    TableGridView(rows: metrics.bottomRows,
                                  cols: metrics.bodyCols,
                                  cellSize: cellSize)
                        .frame(width: metrics.bodyWidth, height: metrics.bottomHeight, alignment: .topLeading)
                        .offset(x: metrics.leftWidth, y: metrics.topHeight + metrics.bodyHeight)
                        .allowsHitTesting(false)
                }

                TableCellOverlay(table: table,
                                 metrics: metrics,
                                 selectedCell: selectedCell,
                                 onSelect: { selection in
                                     viewModel.selectCell(selection)
                                 },
                                 onCommit: { selection, value in
                                     viewModel.setCellValue(tableId: selection.tableId,
                                                            region: selection.region,
                                                            row: selection.row,
                                                            col: selection.col,
                                                            rawValue: value)
                                 })
                    .frame(width: metrics.totalWidth, height: metrics.totalHeight, alignment: .topLeading)
            }
            .frame(width: CGFloat(width), height: CGFloat(height), alignment: .topLeading)
            .clipped()

            Text(table.name)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(4)
                .padding(.leading, 12)
                .offset(y: -8)
                .gesture(moveGesture)
                .onTapGesture {
                    viewModel.selectTable(table.id)
                }
        }
        .frame(width: CGFloat(width), height: CGFloat(height), alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color.secondary)
                .frame(width: 10, height: 10)
                .cornerRadius(2)
                .padding(4)
                .gesture(resizeGesture())
        }
        .position(x: CGFloat(centerX), y: CGFloat(centerY))
    }

    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .named(CanvasCoordinateSpace.name))
            .onChanged { value in
                guard !isResizing else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !isResizing else { return }
                let newRect = Rect(
                    x: table.rect.x + Double(value.translation.width),
                    y: table.rect.y + Double(value.translation.height),
                    width: table.rect.width,
                    height: table.rect.height
                )
                dragOffset = .zero
                viewModel.moveTable(tableId: table.id, to: newRect)
            }
    }

    private func resizeGesture() -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(CanvasCoordinateSpace.name))
            .onChanged { value in
                isResizing = true
                dragOffset = .zero
                let proposedWidth = max(Double(minSize.width), table.rect.width + Double(value.translation.width))
                let proposedHeight = max(Double(minSize.height), table.rect.height + Double(value.translation.height))
                resizeDelta = CGSize(width: proposedWidth - table.rect.width, height: proposedHeight - table.rect.height)
            }
            .onEnded { _ in
                let newWidth = max(Double(minSize.width), table.rect.width + Double(resizeDelta.width))
                let newHeight = max(Double(minSize.height), table.rect.height + Double(resizeDelta.height))
                resizeDelta = .zero
                isResizing = false
                viewModel.resizeTable(tableId: table.id, width: newWidth, height: newHeight)
            }
    }
}
