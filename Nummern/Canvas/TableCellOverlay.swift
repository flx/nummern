import SwiftUI

struct TableGridMetrics: Equatable {
    let cellSize: CGSize
    let bodyRows: Int
    let bodyCols: Int
    let labelBands: LabelBands

    var topRows: Int { labelBands.topRows }
    var bottomRows: Int { labelBands.bottomRows }
    var leftCols: Int { labelBands.leftCols }
    var rightCols: Int { labelBands.rightCols }

    var leftWidth: CGFloat { CGFloat(leftCols) * cellSize.width }
    var rightWidth: CGFloat { CGFloat(rightCols) * cellSize.width }
    var topHeight: CGFloat { CGFloat(topRows) * cellSize.height }
    var bottomHeight: CGFloat { CGFloat(bottomRows) * cellSize.height }
    var bodyWidth: CGFloat { CGFloat(bodyCols) * cellSize.width }
    var bodyHeight: CGFloat { CGFloat(bodyRows) * cellSize.height }

    var totalWidth: CGFloat { leftWidth + bodyWidth + rightWidth }
    var totalHeight: CGFloat { topHeight + bodyHeight + bottomHeight }

    func origin(for region: GridRegion) -> CGPoint {
        switch region {
        case .body:
            return CGPoint(x: leftWidth, y: topHeight)
        case .topLabels:
            return CGPoint(x: leftWidth, y: 0)
        case .bottomLabels:
            return CGPoint(x: leftWidth, y: topHeight + bodyHeight)
        case .leftLabels:
            return CGPoint(x: 0, y: topHeight)
        case .rightLabels:
            return CGPoint(x: leftWidth + bodyWidth, y: topHeight)
        }
    }

    func regionSize(for region: GridRegion) -> CGSize {
        switch region {
        case .body:
            return CGSize(width: bodyWidth, height: bodyHeight)
        case .topLabels:
            return CGSize(width: bodyWidth, height: topHeight)
        case .bottomLabels:
            return CGSize(width: bodyWidth, height: bottomHeight)
        case .leftLabels:
            return CGSize(width: leftWidth, height: bodyHeight)
        case .rightLabels:
            return CGSize(width: rightWidth, height: bodyHeight)
        }
    }

    func cellFrame(region: GridRegion, row: Int, col: Int) -> CGRect {
        let origin = origin(for: region)
        let x = origin.x + CGFloat(col) * cellSize.width
        let y = origin.y + CGFloat(row) * cellSize.height
        return CGRect(x: x, y: y, width: cellSize.width, height: cellSize.height)
    }
}

struct TableCellOverlay: View {
    let table: TableModel
    let metrics: TableGridMetrics
    let selectedCell: CellSelection?
    let onSelect: (CellSelection) -> Void
    let onCommit: (CellSelection, String) -> Void

    @State private var editingCell: CellSelection?
    @State private var editingText: String = ""
    @FocusState private var isEditingFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(selectionGesture)

            cellRegion(region: .topLabels, rows: metrics.topRows, cols: metrics.bodyCols)
            cellRegion(region: .leftLabels, rows: metrics.bodyRows, cols: metrics.leftCols)
            cellRegion(region: .body, rows: metrics.bodyRows, cols: metrics.bodyCols)
            cellRegion(region: .rightLabels, rows: metrics.bodyRows, cols: metrics.rightCols)
            cellRegion(region: .bottomLabels, rows: metrics.bottomRows, cols: metrics.bodyCols)

            selectionOverlay()
        }
        .frame(width: metrics.totalWidth, height: metrics.totalHeight, alignment: .topLeading)
        .onChange(of: selectedCell) { _, newValue in
            guard let editingCell, editingCell != newValue else {
                return
            }
            commitEdit()
        }
    }

    @ViewBuilder
    private func cellRegion(region: GridRegion, rows: Int, cols: Int) -> some View {
        if rows > 0, cols > 0 {
            ForEach(0..<rows, id: \.self) { row in
                ForEach(0..<cols, id: \.self) { col in
                    cellView(region: region, row: row, col: col)
                }
            }
        }
    }

    private func cellView(region: GridRegion, row: Int, col: Int) -> some View {
        let selection = CellSelection(tableId: table.id, region: region, row: row, col: col)
        let frame = metrics.cellFrame(region: region, row: row, col: col)
        let value = displayValue(for: selection)
        let isEditing = editingCell == selection

        return Text(value)
            .font(.system(size: 12))
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(width: metrics.cellSize.width, height: metrics.cellSize.height, alignment: .leading)
            .position(x: frame.midX, y: frame.midY)
            .opacity(isEditing ? 0 : 1)
            .allowsHitTesting(false)
    }

    private func beginEditing(_ selection: CellSelection) {
        if editingCell != selection {
            commitEdit()
            editingCell = selection
            editingText = displayValue(for: selection)
        }
        onSelect(selection)
        isEditingFocused = true
    }

    private func commitEdit() {
        guard let editingCell else {
            return
        }
        let committedCell = editingCell
        let committedText = editingText
        self.editingCell = nil
        isEditingFocused = false
        onCommit(committedCell, committedText)
    }

    private func displayValue(for selection: CellSelection) -> String {
        let key = RangeParser.address(region: selection.region, row: selection.row, col: selection.col)
        return table.cellValues[key]?.displayString ?? ""
    }

    private func selectionOverlay() -> some View {
        Group {
            if let selection = editingCell ?? selectedCell {
                let frame = metrics.cellFrame(region: selection.region, row: selection.row, col: selection.col)
                ZStack {
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 1)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)

                    if editingCell != nil {
                        TextField("", text: $editingText)
                            .textFieldStyle(.plain)
                            .focused($isEditingFocused)
                            .onSubmit {
                                commitEdit()
                            }
                            .padding(.horizontal, 4)
                            .frame(width: frame.width, height: frame.height, alignment: .leading)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
        }
    }

    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                guard let selection = selection(at: value.location) else {
                    return
                }
                beginEditing(selection)
            }
    }

    private func selection(at location: CGPoint) -> CellSelection? {
        let x = location.x
        let y = location.y
        guard x >= 0, y >= 0, x < metrics.totalWidth, y < metrics.totalHeight else {
            return nil
        }

        if metrics.topRows > 0 {
            let minX = metrics.leftWidth
            let maxX = metrics.leftWidth + metrics.bodyWidth
            let minY: CGFloat = 0
            let maxY = metrics.topHeight
            if x >= minX, x < maxX, y >= minY, y < maxY {
                let row = Int((y - minY) / metrics.cellSize.height)
                let col = Int((x - minX) / metrics.cellSize.width)
                return CellSelection(tableId: table.id, region: .topLabels, row: row, col: col)
            }
        }

        if metrics.bottomRows > 0 {
            let minX = metrics.leftWidth
            let maxX = metrics.leftWidth + metrics.bodyWidth
            let minY = metrics.topHeight + metrics.bodyHeight
            let maxY = minY + metrics.bottomHeight
            if x >= minX, x < maxX, y >= minY, y < maxY {
                let row = Int((y - minY) / metrics.cellSize.height)
                let col = Int((x - minX) / metrics.cellSize.width)
                return CellSelection(tableId: table.id, region: .bottomLabels, row: row, col: col)
            }
        }

        if metrics.leftCols > 0 {
            let minX: CGFloat = 0
            let maxX = metrics.leftWidth
            let minY = metrics.topHeight
            let maxY = minY + metrics.bodyHeight
            if x >= minX, x < maxX, y >= minY, y < maxY {
                let row = Int((y - minY) / metrics.cellSize.height)
                let col = Int((x - minX) / metrics.cellSize.width)
                return CellSelection(tableId: table.id, region: .leftLabels, row: row, col: col)
            }
        }

        if metrics.rightCols > 0 {
            let minX = metrics.leftWidth + metrics.bodyWidth
            let maxX = minX + metrics.rightWidth
            let minY = metrics.topHeight
            let maxY = minY + metrics.bodyHeight
            if x >= minX, x < maxX, y >= minY, y < maxY {
                let row = Int((y - minY) / metrics.cellSize.height)
                let col = Int((x - minX) / metrics.cellSize.width)
                return CellSelection(tableId: table.id, region: .rightLabels, row: row, col: col)
            }
        }

        if metrics.bodyRows > 0, metrics.bodyCols > 0 {
            let minX = metrics.leftWidth
            let maxX = metrics.leftWidth + metrics.bodyWidth
            let minY = metrics.topHeight
            let maxY = metrics.topHeight + metrics.bodyHeight
            if x >= minX, x < maxX, y >= minY, y < maxY {
                let row = Int((y - minY) / metrics.cellSize.height)
                let col = Int((x - minX) / metrics.cellSize.width)
                return CellSelection(tableId: table.id, region: .body, row: row, col: col)
            }
        }

        return nil
    }
}
