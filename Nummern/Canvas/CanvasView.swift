import SwiftUI

struct CanvasView: View {
    @ObservedObject var document: NummernDocument

    private var sheet: SheetSnapshot? {
        guard let id = document.selectedSheetId else { return document.project.sheets.first }
        return document.project.sheet(id: id) ?? document.project.sheets.first
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: canvasSize.width, height: canvasSize.height)
                if let sheet {
                    ForEach(sheet.tables) { table in
                        DraggableTable(document: document, table: table)
                    }
                    ForEach(sheet.charts) { chart in
                        DraggableChart(document: document, chart: chart)
                    }
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
            .background(Color(nsColor: .underPageBackgroundColor))
            .contentShape(Rectangle())
            .onTapGesture { document.selection = .none }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var canvasSize: CGSize {
        var maxX: CGFloat = 1200, maxY: CGFloat = 800
        for table in sheet?.tables ?? [] {
            maxX = max(maxX, CGFloat(table.rect.x + table.rect.w) + 120)
            maxY = max(maxY, CGFloat(table.rect.y + table.rect.h) + 120)
        }
        for chart in sheet?.charts ?? [] {
            maxX = max(maxX, CGFloat(chart.rect.x + chart.rect.w) + 120)
            maxY = max(maxY, CGFloat(chart.rect.y + chart.rect.h) + 120)
        }
        return CGSize(width: maxX, height: maxY)
    }
}

/// A chart on the canvas: draggable, selectable, renders computed data.
private struct DraggableChart: View {
    @ObservedObject var document: NummernDocument
    let chart: ChartSnapshot
    @State private var translation: CGSize = .zero

    private var isSelected: Bool {
        if case .chart(let id) = document.selection { return id == chart.id }
        return false
    }

    var body: some View {
        ChartView(chart: chart, table: document.project.table(id: chart.table_id))
            .frame(width: CGFloat(chart.rect.w), height: CGFloat(chart.rect.h))
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.4),
                        lineWidth: isSelected ? 2 : 1))
            .cornerRadius(6)
            .shadow(radius: isSelected ? 4 : 1)
            .offset(x: CGFloat(chart.rect.x) + translation.width,
                    y: CGFloat(chart.rect.y) + translation.height)
            .onTapGesture { document.selection = .chart(chart.id) }
            .gesture(
                DragGesture()
                    .onChanged { translation = $0.translation }
                    .onEnded { value in
                        let newX = chart.rect.x + Double(value.translation.width)
                        let newY = chart.rect.y + Double(value.translation.height)
                        translation = .zero
                        document.previewChartRect(chartId: chart.id, x: newX, y: newY)
                        document.moveChart(chart.id, to: CGPoint(x: newX, y: newY))
                    }
            )
    }
}

/// Wraps a table frame with drag-to-move. Position previews locally during the
/// drag and records a `set_position` command on release.
private struct DraggableTable: View {
    @ObservedObject var document: NummernDocument
    let table: TableSnapshot
    @State private var translation: CGSize = .zero

    private var isSelected: Bool {
        switch document.selection {
        case .table(let id): return id == table.id
        case .cell(let id, _, _): return id == table.id
        default: return false
        }
    }

    private var selectedCell: (row: Int, col: Int)? {
        if case .cell(let id, let r, let c) = document.selection, id == table.id { return (r, c) }
        return nil
    }

    var body: some View {
        TableFrameView(table: table, isSelected: isSelected, selectedCell: selectedCell,
                       onSelectCell: { r, c in document.selectCell(tableId: table.id, row: r, col: c) },
                       onNavigate: { document.moveSelection($0) },
                       onClear: { document.clearSelectedCell() },
                       onEscape: { document.clearSelection() })
            .offset(x: CGFloat(table.rect.x) + translation.width,
                    y: CGFloat(table.rect.y) + translation.height)
            .onTapGesture { document.selection = .table(table.id) }
            .gesture(
                DragGesture()
                    .onChanged { value in translation = value.translation }
                    .onEnded { value in
                        let newX = table.rect.x + Double(value.translation.width)
                        let newY = table.rect.y + Double(value.translation.height)
                        translation = .zero
                        document.previewRect(tableId: table.id, x: newX, y: newY)
                        document.moveTable(table.id, to: CGPoint(x: newX, y: newY))
                    }
            )
    }
}
