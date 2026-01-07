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
                            viewModel.clearSelection()
                        }

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
            let points = chartPoints(table: table)
            if points.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Chart(points) { point in
                    switch chart.chartType {
                    case .line:
                        LineMark(x: .value("Label", point.label),
                                 y: .value("Value", point.value))
                        .foregroundStyle(by: .value("Series", chart.name))
                    case .bar:
                        BarMark(x: .value("Label", point.label),
                                y: .value("Value", point.value))
                        .foregroundStyle(by: .value("Series", chart.name))
                    case .pie:
                        SectorMark(angle: .value("Value", point.value),
                                   innerRadius: .ratio(0.4))
                        .foregroundStyle(by: .value("Label", point.label))
                    }
                }
                .chartLegend(chart.showLegend ? .visible : .hidden)
                .chartXAxis(chart.chartType == .pie ? .hidden : .automatic)
                .chartYAxis(chart.chartType == .pie ? .hidden : .automatic)
                .chartXAxisLabel(chart.xAxisTitle)
                .chartYAxisLabel(chart.yAxisTitle)
            }
        } else {
            Text("Missing table")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
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

    private func chartPoints(table: TableModel) -> [ChartPoint] {
        guard let valueRange = try? RangeParser.parse(chart.valueRange) else {
            return []
        }
        let valueCells = cells(in: valueRange)
        let labelStrings: [String]
        if let labelRange = chart.labelRange,
           let parsedLabelRange = try? RangeParser.parse(labelRange) {
            labelStrings = cells(in: parsedLabelRange).map { cell in
                let key = RangeParser.address(region: parsedLabelRange.region, row: cell.row, col: cell.col)
                let value = table.cellValues[key] ?? .empty
                return value.displayString
            }
        } else {
            labelStrings = []
        }

        var points: [ChartPoint] = []
        for (index, cell) in valueCells.enumerated() {
            let key = RangeParser.address(region: valueRange.region, row: cell.row, col: cell.col)
            let value = table.cellValues[key] ?? .empty
            guard let number = chartNumber(from: value) else {
                continue
            }
            var label = RangeParser.cellLabel(row: cell.row, col: cell.col)
            if index < labelStrings.count {
                let candidate = labelStrings[index]
                if !candidate.isEmpty {
                    label = candidate
                }
            }
            points.append(ChartPoint(id: index, label: label, value: number))
        }
        return points
    }

    private func cells(in range: RangeAddress) -> [CellAddress] {
        let rowStart = min(range.start.row, range.end.row)
        let rowEnd = max(range.start.row, range.end.row)
        let colStart = min(range.start.col, range.end.col)
        let colEnd = max(range.start.col, range.end.col)
        var cells: [CellAddress] = []
        for row in rowStart...rowEnd {
            for col in colStart...colEnd {
                cells.append(CellAddress(row: row, col: col))
            }
        }
        return cells
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
