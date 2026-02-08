import AppKit
import Charts
import SwiftUI

enum CanvasCoordinateSpace {
    static let name = "canvas"
}

struct CanvasView: View {
    let sheet: SheetModel
    @ObservedObject var viewModel: CanvasViewModel

    var body: some View {
        GeometryReader { proxy in
            let contentSize = canvasContentSize(containerSize: proxy.size,
                                               tables: sheet.tables,
                                               charts: sheet.charts)

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !viewModel.isEditing() {
                                viewModel.clearSelection()
                            }
                        }

                    CanvasKeyCaptureView(viewModel: viewModel)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .allowsHitTesting(false)

                    ForEach(sheet.tables, id: \.id) { table in
                        TableCanvasItem(table: table, viewModel: viewModel)
                    }

                    ForEach(sheet.charts, id: \.id) { chart in
                        ChartCanvasItem(chart: chart,
                                        table: sheet.tables.first(where: { $0.id == chart.tableId }),
                                        viewModel: viewModel)
                    }
                }
                .frame(width: contentSize.width, height: contentSize.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .coordinateSpace(name: CanvasCoordinateSpace.name)
            }
        }
    }
}

private func canvasContentSize(containerSize: CGSize, tables: [TableModel], charts: [ChartModel]) -> CGSize {
    let tableMaxX = tables.map { $0.rect.x + $0.rect.width }.max() ?? 0
    let tableMaxY = tables.map { $0.rect.y + $0.rect.height }.max() ?? 0
    let chartMaxX = charts.map { $0.rect.x + $0.rect.width }.max() ?? 0
    let chartMaxY = charts.map { $0.rect.y + $0.rect.height }.max() ?? 0
    let maxX = max(tableMaxX, chartMaxX)
    let maxY = max(tableMaxY, chartMaxY)
    let width = max(containerSize.width, CGFloat(maxX))
    let height = max(containerSize.height, CGFloat(maxY))
    return CGSize(width: width, height: height)
}

struct TableCanvasItem: View {
    let table: TableModel
    @ObservedObject var viewModel: CanvasViewModel

    @State private var dragOffset: CGSize = .zero
    @State private var canMoveFromCurrentDrag = false
    @State private var isResizing = false
    @State private var previewBodyRows: Int?
    @State private var previewBodyCols: Int?
    private let frameDragInset: CGFloat = 10

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
        let selectedRanges = viewModel.selectionRanges(for: table.id)
        let activeRange = viewModel.activeRange(for: table.id)

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
                                 selectedRanges: selectedRanges,
                                 activeRange: activeRange,
                                 activeEdit: viewModel.activeFormulaEdit,
                                 pendingReferenceInsert: viewModel.pendingReferenceInsert,
                                 pendingEditRequest: viewModel.pendingEditRequest,
                                 highlightState: viewModel.formulaHighlightState,
                                 onReplaceSelection: { range, activeCell, anchor in
                                     viewModel.replaceSelection(with: range,
                                                                activeCell: activeCell,
                                                                anchor: anchor)
                                 },
                                 onAddSelection: { range, activeCell in
                                     viewModel.addSelection(range: range, activeCell: activeCell)
                                 },
                                 onToggleSelection: { cell in
                                     viewModel.toggleSelection(cell: cell)
                                 },
                                 onExtendSelection: { cell, addRange in
                                     viewModel.extendSelection(to: cell, addRange: addRange)
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
                                 onCommitRange: { range, value in
                                     viewModel.setRangeValue(range: range, rawValue: value)
                                 },
                                 onHighlightChange: { state in
                                     viewModel.setFormulaHighlights(state)
                                 },
                                 onCancelEditing: {
                                     viewModel.clearSelection()
                                 },
                                 onEndEditing: {
                                     viewModel.endFormulaEdit()
                                 },
                                 onRequestReferenceInsert: { start, end in
                                     viewModel.requestReferenceInsert(start: start, end: end)
                                 },
                                 onConsumeReferenceInsert: { request in
                                     viewModel.consumeReferenceInsert(request)
                                 },
                                 onConsumeEditRequest: { request in
                                     viewModel.consumeEditRequest(request)
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
                .onTapGesture {
                    viewModel.selectTable(table.id)
                }
        }
        .frame(width: CGFloat(width), height: CGFloat(height), alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(moveGesture(itemSize: CGSize(width: CGFloat(width), height: CGFloat(height))))
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

    private func moveGesture(itemSize: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { value in
                guard !isResizing else { return }
                if !canMoveFromCurrentDrag {
                    canMoveFromCurrentDrag = shouldMoveFromFrame(startLocation: value.startLocation,
                                                                 itemSize: itemSize)
                }
                guard canMoveFromCurrentDrag else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                defer {
                    canMoveFromCurrentDrag = false
                }
                guard !isResizing else { return }
                guard canMoveFromCurrentDrag else {
                    dragOffset = .zero
                    return
                }
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

    private func shouldMoveFromFrame(startLocation: CGPoint, itemSize: CGSize) -> Bool {
        let fullRect = CGRect(origin: .zero, size: itemSize)
        guard fullRect.contains(startLocation) else {
            return false
        }
        let resizeHotspot = CGRect(x: max(0, itemSize.width - 24),
                                   y: max(0, itemSize.height - 24),
                                   width: 24,
                                   height: 24)
        if resizeHotspot.contains(startLocation) {
            return false
        }
        let inset = min(frameDragInset, min(itemSize.width, itemSize.height) / 2)
        let innerRect = fullRect.insetBy(dx: inset, dy: inset)
        return !innerRect.contains(startLocation)
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

struct ChartCanvasItem: View {
    let chart: ChartModel
    let table: TableModel?
    @ObservedObject var viewModel: CanvasViewModel

    @State private var dragOffset: CGSize = .zero
    @State private var isResizing = false
    @State private var previewSize: CGSize?

    var body: some View {
        let baseSize = CGSize(width: chart.rect.width, height: chart.rect.height)
        let size = previewSize ?? baseSize
        let originX = chart.rect.x + Double(dragOffset.width)
        let originY = chart.rect.y + Double(dragOffset.height)
        let centerX = originX + Double(size.width) / 2.0
        let centerY = originY + Double(size.height) / 2.0
        let isSelected = viewModel.selectedChartId == chart.id

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.secondary,
                                lineWidth: isSelected ? 2 : 1)
                )

            chartContent()
                .padding(12)

            if !chartTitle.isEmpty {
                Text(chartTitle)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(4)
                    .padding(.leading, 8)
                    .padding(.top, 8)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color.secondary)
                .frame(width: 10, height: 10)
                .cornerRadius(2)
                .padding(6)
                .gesture(resizeGesture(baseSize: baseSize))
        }
        .position(x: centerX, y: centerY)
        .gesture(moveGesture())
        .onTapGesture {
            viewModel.selectChart(chart.id)
        }
    }

    private var chartTitle: String {
        chart.title.isEmpty ? chart.name : chart.title
    }

    @ViewBuilder
    private func chartContent() -> some View {
        if let table {
            switch chart.chartType {
            case .pie:
                let points = piePoints(table: table)
                if points.isEmpty {
                    noDataView()
                } else {
                    Chart(points) { point in
                        SectorMark(angle: .value("Value", point.value),
                                   innerRadius: .ratio(0.4))
                        .foregroundStyle(by: .value("Label", point.label))
                    }
                    .chartLegend(chart.showLegend ? .visible : .hidden)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                }
            case .line, .bar:
                let points = chartDataPoints(table: table)
                if points.isEmpty {
                    noDataView()
                } else {
                    Chart(points) { point in
                        if chart.chartType == .line {
                            LineMark(x: .value("Label", point.label),
                                     y: .value("Value", point.value))
                            .foregroundStyle(by: .value("Series", point.series))
                        } else {
                            BarMark(x: .value("Label", point.label),
                                    y: .value("Value", point.value))
                            .foregroundStyle(by: .value("Series", point.series))
                        }
                    }
                    .chartLegend(chart.showLegend ? .visible : .hidden)
                    .chartXAxis(.automatic)
                    .chartYAxis(.automatic)
                    .chartXAxisLabel(chart.xAxisTitle)
                    .chartYAxisLabel(chart.yAxisTitle)
                }
            }
        } else {
            Text("Missing table")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func noDataView() -> some View {
        Text("No data")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func moveGesture() -> some Gesture {
        DragGesture(coordinateSpace: .named(CanvasCoordinateSpace.name))
            .onChanged { value in
                guard !isResizing else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !isResizing else { return }
                let newRect = Rect(x: chart.rect.x + Double(value.translation.width),
                                   y: chart.rect.y + Double(value.translation.height),
                                   width: chart.rect.width,
                                   height: chart.rect.height)
                dragOffset = .zero
                viewModel.moveChart(chartId: chart.id, to: newRect)
            }
    }

    private func resizeGesture(baseSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(CanvasCoordinateSpace.name))
            .onChanged { value in
                isResizing = true
                dragOffset = .zero
                let width = max(CanvasChartSizing.minSize.width, baseSize.width + value.translation.width)
                let height = max(CanvasChartSizing.minSize.height, baseSize.height + value.translation.height)
                previewSize = CGSize(width: width, height: height)
            }
            .onEnded { value in
                let width = max(CanvasChartSizing.minSize.width, baseSize.width + value.translation.width)
                let height = max(CanvasChartSizing.minSize.height, baseSize.height + value.translation.height)
                previewSize = nil
                isResizing = false
                let newRect = Rect(x: chart.rect.x, y: chart.rect.y, width: Double(width), height: Double(height))
                viewModel.updateChartRect(chartId: chart.id, rect: newRect)
            }
    }

    private func chartDataPoints(table: TableModel) -> [ChartDataPoint] {
        let series = chartSeries(table: table)
        return series.flatMap { series in
            series.points.map { point in
                ChartDataPoint(id: "\(series.name)-\(point.id)",
                               label: point.label,
                               value: point.value,
                               series: series.name)
            }
        }
    }

    private func piePoints(table: TableModel) -> [ChartPoint] {
        guard let first = chartSeries(table: table).first else {
            return []
        }
        return first.points
    }

    private func chartSeries(table: TableModel) -> [ChartSeries] {
        guard let valueRange = try? RangeParser.parse(chart.valueRange) else {
            return []
        }
        let rowStart = min(valueRange.start.row, valueRange.end.row)
        let rowEnd = max(valueRange.start.row, valueRange.end.row)
        let colStart = min(valueRange.start.col, valueRange.end.col)
        let colEnd = max(valueRange.start.col, valueRange.end.col)
        guard rowStart <= rowEnd, colStart <= colEnd else {
            return []
        }

        let labelsByRow = labelStringsByRow(table: table,
                                            valueRange: valueRange,
                                            rowStart: rowStart,
                                            rowEnd: rowEnd)
        let seriesNames = seriesNamesForColumns(table: table,
                                                 colStart: colStart,
                                                 colEnd: colEnd)

        var seriesList: [ChartSeries] = []
        for (offset, col) in (colStart...colEnd).enumerated() {
            let seriesName = seriesNames.indices.contains(offset)
                ? seriesNames[offset]
                : RangeParser.columnLabel(from: col)
            var points: [ChartPoint] = []
            for (rowOffset, row) in (rowStart...rowEnd).enumerated() {
                let key = RangeParser.address(region: valueRange.region, row: row, col: col)
                let value = table.cellValues[key] ?? .empty
                guard let number = chartNumber(from: value) else {
                    continue
                }
                let label = labelForRow(row: row,
                                        rowOffset: rowOffset,
                                        fallbackColumn: col,
                                        labelsByRow: labelsByRow)
                points.append(ChartPoint(id: rowOffset, label: label, value: number))
            }
            seriesList.append(ChartSeries(id: offset, name: seriesName, points: points))
        }
        return seriesList
    }

    private func labelStringsByRow(table: TableModel,
                                   valueRange: RangeAddress,
                                   rowStart: Int,
                                   rowEnd: Int) -> [String] {
        guard let labelRange = chart.labelRange,
              let parsedLabelRange = try? RangeParser.parse(labelRange) else {
            return []
        }
        let labelRowStart = min(parsedLabelRange.start.row, parsedLabelRange.end.row)
        let labelRowEnd = max(parsedLabelRange.start.row, parsedLabelRange.end.row)
        let labelCol = min(parsedLabelRange.start.col, parsedLabelRange.end.col)
        var labels: [String] = []
        for row in rowStart...rowEnd {
            if row < labelRowStart || row > labelRowEnd {
                labels.append("")
                continue
            }
            let key = RangeParser.address(region: parsedLabelRange.region, row: row, col: labelCol)
            let value = table.cellValues[key] ?? .empty
            labels.append(value.displayString)
        }
        return labels
    }

    private func seriesNamesForColumns(table: TableModel,
                                       colStart: Int,
                                       colEnd: Int) -> [String] {
        guard table.gridSpec.labelBands.topRows > 0 else {
            return (colStart...colEnd).map { RangeParser.columnLabel(from: $0) }
        }
        var names: [String] = []
        for col in colStart...colEnd {
            let key = RangeParser.address(region: .topLabels, row: 0, col: col)
            let value = table.cellValues[key] ?? .empty
            let name = value.displayString
            names.append(name.isEmpty ? RangeParser.columnLabel(from: col) : name)
        }
        return names
    }

    private func labelForRow(row: Int,
                             rowOffset: Int,
                             fallbackColumn: Int,
                             labelsByRow: [String]) -> String {
        if labelsByRow.indices.contains(rowOffset) {
            let candidate = labelsByRow[rowOffset]
            if !candidate.isEmpty {
                return candidate
            }
        }
        return RangeParser.cellLabel(row: row, col: fallbackColumn)
    }

    private func chartNumber(from value: CellValue) -> Double? {
        switch value {
        case .number(let number):
            return number
        case .bool(let flag):
            return flag ? 1.0 : 0.0
        case .date(let date):
            return date.timeIntervalSinceReferenceDate
        case .time(let seconds):
            return seconds
        case .string, .empty:
            return nil
        }
    }
}

private struct ChartPoint: Identifiable {
    let id: Int
    let label: String
    let value: Double
}

private struct ChartSeries: Identifiable {
    let id: Int
    let name: String
    let points: [ChartPoint]
}

private struct ChartDataPoint: Identifiable {
    let id: String
    let label: String
    let value: Double
    let series: String
}

private struct CanvasKeyCaptureView: NSViewRepresentable {
    @ObservedObject var viewModel: CanvasViewModel

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.viewModel = viewModel
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.viewModel = viewModel
        if viewModel.needsCanvasKeyFocus,
           nsView.window?.firstResponder != nsView {
            nsView.window?.makeFirstResponder(nsView)
            viewModel.consumeCanvasKeyFocus()
        }
    }

    final class KeyCaptureNSView: NSView {
        weak var viewModel: CanvasViewModel?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if viewModel?.handleKeyDown(event) == true {
                return
            }
            if let next = nextResponder {
                next.keyDown(with: event)
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
