import SwiftUI
import AppKit

/// SwiftUI wrapper around the virtualized AppKit grid renderer.
struct TableGridView: NSViewRepresentable {
    let table: TableSnapshot
    var selectedCell: (row: Int, col: Int)?
    var onSelectCell: ((Int, Int) -> Void)?

    func makeNSView(context: Context) -> GridContentView {
        let view = GridContentView()
        view.configure(table: table, selected: selectedCell, onSelect: onSelectCell)
        return view
    }

    func updateNSView(_ view: GridContentView, context: Context) {
        view.configure(table: table, selected: selectedCell, onSelect: onSelectCell)
    }
}

/// Layer-backed grid that draws only the cells intersecting the dirty rect, so
/// cost scales with what's visible rather than table size (README §12.2).
final class GridContentView: NSView {
    private var table: TableSnapshot?
    private var selected: (row: Int, col: Int)?
    private var onSelect: ((Int, Int) -> Void)?

    private let cw = GridGeometry.cellWidth
    private let ch = GridGeometry.cellHeight

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        guard let table else { return .zero }
        return GridGeometry.size(table)
    }

    func configure(table: TableSnapshot, selected: (row: Int, col: Int)?,
                   onSelect: ((Int, Int) -> Void)?) {
        let changed = self.table != table || self.selected?.row != selected?.row
            || self.selected?.col != selected?.col
        self.table = table
        self.selected = selected
        self.onSelect = onSelect
        if changed {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let table else { return }
        let totalRows = GridGeometry.totalRows(table)
        let totalCols = GridGeometry.totalCols(table)
        let rows = GridGeometry.visibleRows(in: dirtyRect, totalRows: totalRows)
        let cols = GridGeometry.visibleCols(in: dirtyRect, totalCols: totalCols)
        let border = NSColor.gridColor.withAlphaComponent(0.5)

        for gr in rows {
            for gc in cols {
                let info = GridGeometry.cell(table, gr: gr, gc: gc)
                let cellRect = NSRect(x: CGFloat(gc) * cw, y: CGFloat(gr) * ch, width: cw, height: ch)
                background(for: info.region).setFill()
                cellRect.fill()

                let isSelected = info.region == .body
                    && selected?.row == info.row && selected?.col == info.col
                if isSelected {
                    NSColor.controlAccentColor.setStroke()
                    let path = NSBezierPath(rect: cellRect.insetBy(dx: 1, dy: 1))
                    path.lineWidth = 2
                    path.stroke()
                } else {
                    border.setStroke()
                    let path = NSBezierPath(rect: cellRect)
                    path.lineWidth = 0.5
                    path.stroke()
                }

                drawText(info, in: cellRect)
            }
        }
    }

    private func drawText(_ info: GridGeometry.CellInfo, in rect: NSRect) {
        let text = info.value.displayText()
        guard !text.isEmpty else { return }
        let isLabel = info.region != .body && info.region != .corner
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        if case .number = info.value { para.alignment = .right } else { para.alignment = .left }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: isLabel
                ? NSFont.systemFont(ofSize: 11, weight: .semibold)
                : NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ]
        let inset = rect.insetBy(dx: 4, dy: 4)
        NSAttributedString(string: text, attributes: attrs).draw(in: inset)
    }

    private func background(for region: GridGeometry.Region) -> NSColor {
        switch region {
        case .body: return .textBackgroundColor
        case .corner: return NSColor.gridColor.withAlphaComponent(0.12)
        default: return NSColor.gridColor.withAlphaComponent(0.2)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let table else { return }
        let p = convert(event.locationInWindow, from: nil)
        let gc = Int((p.x / cw).rounded(.down))
        let gr = Int((p.y / ch).rounded(.down))
        guard gr >= 0, gc >= 0, gr < GridGeometry.totalRows(table), gc < GridGeometry.totalCols(table)
        else { return }
        let info = GridGeometry.cell(table, gr: gr, gc: gc)
        if info.region == .body { onSelect?(info.row, info.col) }
    }
}
