import SwiftUI

private enum CanvasCoordinateSpace {
    static let name = "canvas"
}

struct CanvasView: View {
    let sheet: SheetModel
    @ObservedObject var viewModel: CanvasViewModel

    var body: some View {
        GeometryReader { proxy in
            let contentSize = canvasContentSize(containerSize: proxy.size, tables: sheet.tables)

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
                .frame(width: contentSize.width, height: contentSize.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .coordinateSpace(name: CanvasCoordinateSpace.name)
            }
        }
    }
}

private func canvasContentSize(containerSize: CGSize, tables: [TableModel]) -> CGSize {
    let maxX = tables.map { $0.rect.x + $0.rect.width }.max() ?? 0
    let maxY = tables.map { $0.rect.y + $0.rect.height }.max() ?? 0
    let width = max(containerSize.width, CGFloat(maxX))
    let height = max(containerSize.height, CGFloat(maxY))
    return CGSize(width: width, height: height)
}

struct TableCanvasItem: View {
    let table: TableModel
    @ObservedObject var viewModel: CanvasViewModel

    @State private var dragOffset: CGSize = .zero
    @State private var isResizing = false
    @State private var previewBodyRows: Int?
    @State private var previewBodyCols: Int?

    var body: some View {
        let bodyRows = previewBodyRows ?? table.gridSpec.bodyRows
        let bodyCols = previewBodyCols ?? table.gridSpec.bodyCols
        let metrics = TableGridMetrics(cellSize: CanvasGridSizing.cellSize,
                                       bodyRows: bodyRows,
                                       bodyCols: bodyCols,
                                       labelBands: table.gridSpec.labelBands)
        let width = Double(metrics.totalWidth)
        let height = Double(metrics.totalHeight)
        let originX = table.rect.x + Double(dragOffset.width)
        let originY = table.rect.y + Double(dragOffset.height)
        let centerX = originX + width / 2.0
        let centerY = originY + height / 2.0
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
                                  cellSize: CanvasGridSizing.cellSize)
                        .frame(width: metrics.bodyWidth, height: metrics.topHeight, alignment: .topLeading)
                        .offset(x: metrics.leftWidth, y: 0)
                        .allowsHitTesting(false)
                }
                if metrics.leftCols > 0 {
                    TableGridView(rows: metrics.bodyRows,
                                  cols: metrics.leftCols,
                                  cellSize: CanvasGridSizing.cellSize)
                        .frame(width: metrics.leftWidth, height: metrics.bodyHeight, alignment: .topLeading)
                        .offset(x: 0, y: metrics.topHeight)
                        .allowsHitTesting(false)
                }
                TableGridView(rows: metrics.bodyRows,
                              cols: metrics.bodyCols,
                              cellSize: CanvasGridSizing.cellSize)
                    .frame(width: metrics.bodyWidth, height: metrics.bodyHeight, alignment: .topLeading)
                    .offset(x: metrics.leftWidth, y: metrics.topHeight)
                    .allowsHitTesting(false)
                if metrics.rightCols > 0 {
                    TableGridView(rows: metrics.bodyRows,
                                  cols: metrics.rightCols,
                                  cellSize: CanvasGridSizing.cellSize)
                        .frame(width: metrics.rightWidth, height: metrics.bodyHeight, alignment: .topLeading)
                        .offset(x: metrics.leftWidth + metrics.bodyWidth, y: metrics.topHeight)
                        .allowsHitTesting(false)
                }
                if metrics.bottomRows > 0 {
                    TableGridView(rows: metrics.bottomRows,
                                  cols: metrics.bodyCols,
                                  cellSize: CanvasGridSizing.cellSize)
                        .frame(width: metrics.bodyWidth, height: metrics.bottomHeight, alignment: .topLeading)
                        .offset(x: metrics.leftWidth, y: metrics.topHeight + metrics.bodyHeight)
                        .allowsHitTesting(false)
                }
                if metrics.topRows > 0 || metrics.bottomRows > 0 || metrics.leftCols > 0 || metrics.rightCols > 0 {
                    Path { path in
                        let leftX = metrics.leftWidth
                        let rightX = metrics.leftWidth + metrics.bodyWidth
                        let topY = metrics.topHeight
                        let bottomY = metrics.topHeight + metrics.bodyHeight

                        if metrics.topRows > 0 {
                            path.move(to: CGPoint(x: leftX, y: topY))
                            path.addLine(to: CGPoint(x: rightX, y: topY))
                        }
                        if metrics.bottomRows > 0 {
                            path.move(to: CGPoint(x: leftX, y: bottomY))
                            path.addLine(to: CGPoint(x: rightX, y: bottomY))
                        }
                        if metrics.leftCols > 0 {
                            path.move(to: CGPoint(x: leftX, y: topY))
                            path.addLine(to: CGPoint(x: leftX, y: bottomY))
                        }
                        if metrics.rightCols > 0 {
                            path.move(to: CGPoint(x: rightX, y: topY))
                            path.addLine(to: CGPoint(x: rightX, y: bottomY))
                        }
                    }
                    .stroke(Color(nsColor: .gridColor), lineWidth: 2)
                    .allowsHitTesting(false)
                }

                TableCellOverlay(table: table,
                                 metrics: metrics,
                                 selectedCell: selectedCell,
                                 activeEdit: viewModel.activeFormulaEdit,
                                 pendingReferenceInsert: viewModel.pendingReferenceInsert,
                                 highlightState: viewModel.formulaHighlightState,
                                 onSelect: { selection in
                                     viewModel.selectCell(selection)
                                 },
                                 onBeginEditing: { selection in
                                     viewModel.beginFormulaEdit(selection)
                                 },
                                 onCommit: { selection, value in
                                     viewModel.setCellValue(tableId: selection.tableId,
                                                            region: selection.region,
                                                            row: selection.row,
                                                            col: selection.col,
                                                            rawValue: value)
                                 },
                                 onHighlightChange: { state in
                                     viewModel.setFormulaHighlights(state)
                                 },
                                 onEndEditing: {
                                     viewModel.endFormulaEdit()
                                 },
                                 onRequestReferenceInsert: { start, end in
                                     viewModel.requestReferenceInsert(start: start, end: end)
                                 },
                                 onConsumeReferenceInsert: { request in
                                     viewModel.consumeReferenceInsert(request)
                                 })
                    .frame(width: metrics.totalWidth, height: metrics.totalHeight, alignment: .topLeading)
            }
            .frame(width: CGFloat(width), height: CGFloat(height), alignment: .topLeading)
            .clipped()

            Text(table.id)
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
                .onTapGesture(count: 2) {
                    viewModel.minimizeTable(tableId: table.id)
                }
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
                let metrics = TableGridMetrics(cellSize: CanvasGridSizing.cellSize,
                                               bodyRows: table.gridSpec.bodyRows,
                                               bodyCols: table.gridSpec.bodyCols,
                                               labelBands: table.gridSpec.labelBands)
                let newRect = Rect(
                    x: table.rect.x + Double(value.translation.width),
                    y: table.rect.y + Double(value.translation.height),
                    width: Double(metrics.totalWidth),
                    height: Double(metrics.totalHeight)
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
                let size = resizedBodySize(for: value.translation)
                previewBodyRows = size.rows
                previewBodyCols = size.cols
            }
            .onEnded { value in
                let size = resizedBodySize(for: value.translation)
                previewBodyRows = nil
                previewBodyCols = nil
                isResizing = false
                if size.rows != table.gridSpec.bodyRows || size.cols != table.gridSpec.bodyCols {
                    viewModel.setBodySize(tableId: table.id, rows: size.rows, cols: size.cols)
                }
            }
    }

    private func resizedBodySize(for translation: CGSize) -> (rows: Int, cols: Int) {
        let baseMetrics = TableGridMetrics(cellSize: CanvasGridSizing.cellSize,
                                           bodyRows: table.gridSpec.bodyRows,
                                           bodyCols: table.gridSpec.bodyCols,
                                           labelBands: table.gridSpec.labelBands)
        let proposedWidth = baseMetrics.totalWidth + translation.width
        let proposedHeight = baseMetrics.totalHeight + translation.height
        let minCols = CanvasGridSizing.minBodyCols
        let minRows = CanvasGridSizing.minBodyRows
        let bodyWidth = max(CanvasGridSizing.cellSize.width * CGFloat(minCols),
                            proposedWidth - baseMetrics.leftWidth - baseMetrics.rightWidth)
        let bodyHeight = max(CanvasGridSizing.cellSize.height * CGFloat(minRows),
                             proposedHeight - baseMetrics.topHeight - baseMetrics.bottomHeight)
        let cols = max(minCols, Int(floor(bodyWidth / CanvasGridSizing.cellSize.width)))
        let rows = max(minRows, Int(floor(bodyHeight / CanvasGridSizing.cellSize.height)))
        return (rows, cols)
    }
}
