import AppKit
import Foundation
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
    let highlightState: FormulaHighlightState?
    let onSelect: (CellSelection) -> Void
    let onCommit: (CellSelection, String) -> Void
    let onHighlightChange: (FormulaHighlightState?) -> Void

    @State private var editingCell: CellSelection?
    @State private var editingText: String = ""
    @State private var originalEditingText: String = ""
    @State private var isEditingFocused = false
    @State private var dragStartSelection: CellSelection?
    @State private var dragCurrentSelection: CellSelection?

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
        .onChange(of: editingText) { _ in
            updateHighlightState()
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
            editingCell = selection
            editingText = editingValue(for: selection)
            originalEditingText = editingText
        }
        onSelect(selection)
        isEditingFocused = true
        updateHighlightState()
    }

    private func commitEdit() {
        guard let editingCell else {
            return
        }
        let committedCell = editingCell
        let committedText = editingText
        self.editingCell = nil
        isEditingFocused = false
        onHighlightChange(nil)
        onCommit(committedCell, committedText)
    }

    private func cancelEdit() {
        editingText = originalEditingText
        editingCell = nil
        isEditingFocused = false
        onHighlightChange(nil)
    }

    private func displayValue(for selection: CellSelection) -> String {
        let key = RangeParser.address(region: selection.region, row: selection.row, col: selection.col)
        if let value = table.cellValues[key], value != .empty {
            return value.displayString
        }
        if selection.region == .body,
           let formula = table.formulas[key]?.formula,
           !formula.isEmpty {
            return formula
        }
        return ""
    }

    private func editingValue(for selection: CellSelection) -> String {
        let key = RangeParser.address(region: selection.region, row: selection.row, col: selection.col)
        if selection.region == .body,
           let formula = table.formulas[key]?.formula,
           !formula.isEmpty {
            return formula
        }
        return displayValue(for: selection)
    }

    private func selectionOverlay() -> some View {
        Group {
            ZStack {
                ForEach(referenceHighlights(from: highlightState)) { highlight in
                    Rectangle()
                        .fill(highlight.color.opacity(0.12))
                        .frame(width: highlight.rect.width, height: highlight.rect.height)
                        .position(x: highlight.rect.midX, y: highlight.rect.midY)
                        .allowsHitTesting(false)
                    Rectangle()
                        .stroke(highlight.color, lineWidth: 1.5)
                        .frame(width: highlight.rect.width, height: highlight.rect.height)
                        .position(x: highlight.rect.midX, y: highlight.rect.midY)
                        .allowsHitTesting(false)
                }

                if let dragRect = dragSelectionRect() {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: dragRect.width, height: dragRect.height)
                        .position(x: dragRect.midX, y: dragRect.midY)
                        .allowsHitTesting(false)
                    Rectangle()
                        .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
                        .frame(width: dragRect.width, height: dragRect.height)
                        .position(x: dragRect.midX, y: dragRect.midY)
                        .allowsHitTesting(false)
                }

                if let selection = editingCell ?? selectedCell {
                    let frame = metrics.cellFrame(region: selection.region, row: selection.row, col: selection.col)
                    let editorWidth = editorWidth(for: selection, frame: frame)
                    let editorPosition = CGPoint(x: frame.minX + editorWidth / 2, y: frame.midY)
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 1)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)

                    if editingCell != nil {
                        FormulaTextEditor(text: $editingText,
                                          highlights: textHighlights(from: highlightState),
                                          font: NSFont.systemFont(ofSize: 12),
                                          isFirstResponder: isEditingFocused,
                                          onSubmit: commitEdit,
                                          onCancel: cancelEdit)
                            .frame(width: editorWidth, height: frame.height, alignment: .leading)
                            .position(x: editorPosition.x, y: editorPosition.y)
                    }
                }
            }
        }
    }

    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard editingCell != nil else {
                    return
                }
                if dragStartSelection == nil {
                    dragStartSelection = selection(at: value.location)
                }
                if let selection = selection(at: value.location) {
                    dragCurrentSelection = selection
                }
            }
            .onEnded { value in
                let selectionAtEnd = selection(at: value.location)
                if let editingCell {
                    let start = dragStartSelection ?? selectionAtEnd
                    let end = dragCurrentSelection ?? selectionAtEnd
                    dragStartSelection = nil
                    dragCurrentSelection = nil
                    guard let start, let end else {
                        return
                    }
                    if start == editingCell, end == editingCell {
                        isEditingFocused = true
                        return
                    }
                    handleReferenceInsertRange(start: start, end: end, editingCell: editingCell)
                    return
                }
                guard let selection = selectionAtEnd else {
                    return
                }
                beginEditing(selection)
            }
    }

    private func handleReferenceInsert(from selection: CellSelection, editingCell: CellSelection) {
        guard editingCell.region == .body else {
            onSelect(selection)
            return
        }
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("=") else {
            onSelect(selection)
            return
        }
        let reference = formulaReference(for: selection, editingCell: editingCell)
        editingText += reference
        onSelect(selection)
        isEditingFocused = true
    }

    private func handleReferenceInsertRange(start: CellSelection,
                                            end: CellSelection,
                                            editingCell: CellSelection) {
        guard editingCell.region == .body else {
            onSelect(end)
            return
        }
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("=") else {
            onSelect(end)
            return
        }
        let reference = formulaReferenceRange(start: start, end: end, editingCell: editingCell)
        editingText += reference
        onSelect(end)
        isEditingFocused = true
    }

    private func formulaReference(for selection: CellSelection, editingCell: CellSelection) -> String {
        let cellLabel = RangeParser.cellLabel(row: selection.row, col: selection.col)
        let regionPrefix: String
        if selection.region == .body {
            regionPrefix = cellLabel
        } else {
            regionPrefix = "\(selection.region.rawValue)[\(cellLabel)]"
        }
        if selection.tableId == editingCell.tableId {
            return regionPrefix
        }
        return "\(selection.tableId)::\(regionPrefix)"
    }

    private func formulaReferenceRange(start: CellSelection,
                                       end: CellSelection,
                                       editingCell: CellSelection) -> String {
        guard start.region == end.region else {
            return formulaReference(for: end, editingCell: editingCell)
        }

        let rowStart = min(start.row, end.row)
        let rowEnd = max(start.row, end.row)
        let colStart = min(start.col, end.col)
        let colEnd = max(start.col, end.col)
        if rowStart == rowEnd, colStart == colEnd {
            let single = CellSelection(tableId: start.tableId,
                                       region: start.region,
                                       row: rowStart,
                                       col: colStart)
            return formulaReference(for: single, editingCell: editingCell)
        }

        let startLabel = RangeParser.cellLabel(row: rowStart, col: colStart)
        let endLabel = RangeParser.cellLabel(row: rowEnd, col: colEnd)
        let rangeLabel: String
        if start.region == .body {
            rangeLabel = "\(startLabel):\(endLabel)"
        } else {
            rangeLabel = "\(start.region.rawValue)[\(startLabel):\(endLabel)]"
        }
        if start.tableId == editingCell.tableId {
            return rangeLabel
        }
        return "\(start.tableId)::\(rangeLabel)"
    }

    private func dragSelectionRect() -> CGRect? {
        guard editingCell != nil,
              let start = dragStartSelection,
              let end = dragCurrentSelection else {
            return nil
        }
        guard start.region == end.region else {
            return metrics.cellFrame(region: end.region, row: end.row, col: end.col)
        }

        let rowStart = min(start.row, end.row)
        let rowEnd = max(start.row, end.row)
        let colStart = min(start.col, end.col)
        let colEnd = max(start.col, end.col)

        let startFrame = metrics.cellFrame(region: start.region, row: rowStart, col: colStart)
        let endFrame = metrics.cellFrame(region: start.region, row: rowEnd, col: colEnd)
        return startFrame.union(endFrame)
    }

    private func editorWidth(for selection: CellSelection, frame: CGRect) -> CGFloat {
        let origin = metrics.origin(for: selection.region)
        let size = metrics.regionSize(for: selection.region)
        let maxWidth = origin.x + size.width - frame.minX
        return max(frame.width, maxWidth)
    }

    private struct ReferenceHighlight: Identifiable {
        let id = UUID()
        let rect: CGRect
        let color: Color
    }

    private func updateHighlightState() {
        guard let editingCell else {
            return
        }
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("=") else {
            onHighlightChange(nil)
            return
        }
        let result = extractReferences(from: editingText, defaultTableId: editingCell.tableId)
        if result.references.isEmpty {
            onHighlightChange(nil)
            return
        }
        onHighlightChange(FormulaHighlightState(tableId: editingCell.tableId,
                                                text: editingText,
                                                references: result.references,
                                                occurrences: result.occurrences))
    }

    private func referenceHighlights(from state: FormulaHighlightState?) -> [ReferenceHighlight] {
        guard let state else {
            return []
        }
        let colors = referenceColors
        var highlights: [ReferenceHighlight] = []
        for (index, reference) in state.references.enumerated() {
            guard reference.tableId == table.id,
                  let rect = referenceRect(for: reference) else {
                continue
            }
            let color = colors[index % colors.count]
            highlights.append(ReferenceHighlight(rect: rect, color: color))
        }
        return highlights
    }

    private func textHighlights(from state: FormulaHighlightState?) -> [FormulaTextHighlight] {
        guard let state,
              state.tableId == table.id,
              !state.occurrences.isEmpty else {
            return []
        }
        let palette = referencePalette
        var colorByReference: [FormulaReferenceKey: NSColor] = [:]
        for (index, reference) in state.references.enumerated() {
            colorByReference[reference] = palette[index % palette.count]
        }
        return state.occurrences.compactMap { occurrence in
            guard let color = colorByReference[occurrence.key] else {
                return nil
            }
            return FormulaTextHighlight(location: occurrence.location,
                                        length: occurrence.length,
                                        color: color)
        }
    }

    private var referencePalette: [NSColor] {
        [
            .systemBlue,
            .systemGreen,
            .systemOrange,
            .systemRed,
            .systemTeal,
            .systemBrown
        ]
    }

    private var referenceColors: [Color] {
        referencePalette.map { Color(nsColor: $0) }
    }

    private func referenceRect(for reference: FormulaReferenceKey) -> CGRect? {
        let (rows, cols) = regionDimensions(for: reference.region)
        guard reference.startRow >= 0, reference.startCol >= 0,
              reference.endRow >= 0, reference.endCol >= 0,
              reference.startRow < rows, reference.endRow < rows,
              reference.startCol < cols, reference.endCol < cols else {
            return nil
        }
        let rowStart = min(reference.startRow, reference.endRow)
        let rowEnd = max(reference.startRow, reference.endRow)
        let colStart = min(reference.startCol, reference.endCol)
        let colEnd = max(reference.startCol, reference.endCol)
        let startFrame = metrics.cellFrame(region: reference.region, row: rowStart, col: colStart)
        let endFrame = metrics.cellFrame(region: reference.region, row: rowEnd, col: colEnd)
        return startFrame.union(endFrame)
    }

    private func regionDimensions(for region: GridRegion) -> (rows: Int, cols: Int) {
        switch region {
        case .body:
            return (metrics.bodyRows, metrics.bodyCols)
        case .topLabels:
            return (metrics.topRows, metrics.bodyCols)
        case .bottomLabels:
            return (metrics.bottomRows, metrics.bodyCols)
        case .leftLabels:
            return (metrics.bodyRows, metrics.leftCols)
        case .rightLabels:
            return (metrics.bodyRows, metrics.rightCols)
        }
    }

    private struct ParsedMatch {
        let range: NSRange
        let tableId: String?
        let regionRaw: String?
        let start: String?
        let end: String?
    }

    private func extractReferences(from formula: String,
                                   defaultTableId: String) -> (references: [FormulaReferenceKey],
                                                               occurrences: [FormulaReferenceOccurrence]) {
        let text = formula
        var matches: [ParsedMatch] = []
        var consumed: [NSRange] = []

        let regionPattern = #"(?i)([A-Za-z0-9_]+::)?(body|top_labels|bottom_labels|left_labels|right_labels)\[(\$?[A-Za-z]+\$?\d+)(?::(\$?[A-Za-z]+\$?\d+))?\]"#
        if let regionRegex = try? NSRegularExpression(pattern: regionPattern) {
            let matchesRaw = regionRegex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
            for match in matchesRaw {
                guard match.numberOfRanges >= 4 else {
                    continue
                }
                let tableId = captureGroup(match, index: 1, in: text)?
                    .replacingOccurrences(of: "::", with: "")
                let regionRaw = captureGroup(match, index: 2, in: text)
                let start = captureGroup(match, index: 3, in: text)
                let end = captureGroup(match, index: 4, in: text) ?? start
                matches.append(ParsedMatch(range: match.range,
                                           tableId: tableId,
                                           regionRaw: regionRaw,
                                           start: start,
                                           end: end))
                consumed.append(match.range)
            }
        }

        let simplePattern = #"(?i)([A-Za-z0-9_]+::)?(\$?[A-Za-z]+\$?\d+)(?::(\$?[A-Za-z]+\$?\d+))?"#
        if let simpleRegex = try? NSRegularExpression(pattern: simplePattern) {
            let matchesRaw = simpleRegex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
            for match in matchesRaw {
                if overlaps(match.range, consumed) {
                    continue
                }
                if !hasValidBoundaries(match.range, in: text) {
                    continue
                }
                let tableId = captureGroup(match, index: 1, in: text)?
                    .replacingOccurrences(of: "::", with: "")
                let start = captureGroup(match, index: 2, in: text)
                let end = captureGroup(match, index: 3, in: text) ?? start
                matches.append(ParsedMatch(range: match.range,
                                           tableId: tableId,
                                           regionRaw: "body",
                                           start: start,
                                           end: end))
            }
        }

        matches.sort { $0.range.location < $1.range.location }

        var references: [FormulaReferenceKey] = []
        var occurrences: [FormulaReferenceOccurrence] = []
        var seen: [FormulaReferenceKey: Int] = [:]

        for match in matches {
            let tableId = match.tableId ?? defaultTableId
            guard let reference = makeReference(tableId: tableId,
                                                regionRaw: match.regionRaw,
                                                start: match.start,
                                                end: match.end) else {
                continue
            }
            if seen[reference] == nil {
                seen[reference] = references.count
                references.append(reference)
            }
            occurrences.append(FormulaReferenceOccurrence(key: reference,
                                                          location: match.range.location,
                                                          length: match.range.length))
        }

        return (references, occurrences)
    }

    private func makeReference(tableId: String,
                               regionRaw: String?,
                               start: String?,
                               end: String?) -> FormulaReferenceKey? {
        guard let regionRaw, let start, let end else {
            return nil
        }
        let regionKey = regionRaw.lowercased()
        guard let region = GridRegion(rawValue: regionKey) else {
            return nil
        }
        let cleanStart = start.replacingOccurrences(of: "$", with: "")
        let cleanEnd = end.replacingOccurrences(of: "$", with: "")
        let rangeString = "\(region.rawValue)[\(cleanStart):\(cleanEnd)]"
        guard let parsed = try? RangeParser.parse(rangeString) else {
            return nil
        }
        return FormulaReferenceKey(tableId: tableId,
                                   region: parsed.region,
                                   startRow: parsed.start.row,
                                   startCol: parsed.start.col,
                                   endRow: parsed.end.row,
                                   endCol: parsed.end.col)
    }

    private func captureGroup(_ match: NSTextCheckingResult,
                              index: Int,
                              in text: String) -> String? {
        guard index < match.numberOfRanges else {
            return nil
        }
        let range = match.range(at: index)
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }

    private func overlaps(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        for existing in ranges {
            let start = max(range.location, existing.location)
            let end = min(range.location + range.length, existing.location + existing.length)
            if start < end {
                return true
            }
        }
        return false
    }

    private func hasValidBoundaries(_ range: NSRange, in text: String) -> Bool {
        guard let swiftRange = Range(range, in: text) else {
            return false
        }
        let lower = swiftRange.lowerBound
        let upper = swiftRange.upperBound
        if lower > text.startIndex {
            let prev = text[text.index(before: lower)]
            if isWordCharacter(prev) {
                return false
            }
        }
        if upper < text.endIndex {
            let next = text[upper]
            if isWordCharacter(next) {
                return false
            }
        }
        return true
    }

    private func isWordCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_" || char == "."
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
