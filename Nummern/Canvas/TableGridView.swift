import AppKit
import SwiftUI

struct TableGridView: NSViewRepresentable {
    let rows: Int
    let cols: Int
    let cellSize: CGSize

    func makeNSView(context: Context) -> GridView {
        GridView(rows: rows, cols: cols, cellSize: cellSize)
    }

    func updateNSView(_ nsView: GridView, context: Context) {
        nsView.rows = rows
        nsView.cols = cols
        nsView.cellSize = cellSize
    }
}

final class GridView: NSView {
    var rows: Int {
        didSet { needsDisplay = true }
    }
    var cols: Int {
        didSet { needsDisplay = true }
    }
    var cellSize: CGSize {
        didSet { needsDisplay = true }
    }

    init(rows: Int, cols: Int, cellSize: CGSize) {
        self.rows = rows
        self.cols = cols
        self.cellSize = cellSize
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        self.rows = 0
        self.cols = 0
        self.cellSize = CGSize(width: 80, height: 24)
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard rows > 0, cols > 0 else {
            return
        }

        let visible = visibleRect
        let range = GridLayoutCalculator.visibleRange(
            visibleRect: visible,
            cellSize: cellSize,
            rows: rows,
            cols: cols
        )

        guard !range.rowRange.isEmpty, !range.colRange.isEmpty else {
            return
        }

        let path = NSBezierPath()
        let strokeColor = NSColor.gridColor
        strokeColor.setStroke()
        path.lineWidth = 0.5

        let startRow = range.rowRange.lowerBound
        let endRow = range.rowRange.upperBound
        let startCol = range.colRange.lowerBound
        let endCol = range.colRange.upperBound

        for row in startRow...endRow {
            let y = CGFloat(row) * cellSize.height
            path.move(to: CGPoint(x: CGFloat(startCol) * cellSize.width, y: y))
            path.line(to: CGPoint(x: CGFloat(endCol) * cellSize.width, y: y))
        }

        for col in startCol...endCol {
            let x = CGFloat(col) * cellSize.width
            path.move(to: CGPoint(x: x, y: CGFloat(startRow) * cellSize.height))
            path.line(to: CGPoint(x: x, y: CGFloat(endRow) * cellSize.height))
        }

        path.stroke()
    }
}
