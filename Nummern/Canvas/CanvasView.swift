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
        return CGSize(width: maxX, height: maxY)
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
                       onSelectCell: { r, c in document.selectCell(tableId: table.id, row: r, col: c) })
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
