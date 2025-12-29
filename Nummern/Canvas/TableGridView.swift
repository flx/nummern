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
        guard rows > 0, cols > 0, cellSize.width > 0, cellSize.height > 0 else {
            return
        }

        let path = NSBezierPath()
        let strokeColor = NSColor.gridColor
        strokeColor.setStroke()
        path.lineWidth = 0.5

        let totalWidth = CGFloat(cols) * cellSize.width
        let totalHeight = CGFloat(rows) * cellSize.height

        for row in 0...rows {
            let y = CGFloat(row) * cellSize.height
            path.move(to: CGPoint(x: 0, y: y))
            path.line(to: CGPoint(x: totalWidth, y: y))
        }

        for col in 0...cols {
            let x = CGFloat(col) * cellSize.width
            path.move(to: CGPoint(x: x, y: 0))
            path.line(to: CGPoint(x: x, y: totalHeight))
        }

        path.stroke()
    }
}
