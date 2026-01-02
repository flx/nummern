import Foundation

struct AddSheetCommand: Command {
    let commandId: String
    let timestamp: Date
    let name: String
    let sheetId: String

    init(commandId: String = ModelID.make(),
         timestamp: Date = Date(),
         name: String,
         sheetId: String) {
        self.commandId = commandId
        self.timestamp = timestamp
        self.name = name
        self.sheetId = sheetId
    }

    func apply(to project: inout ProjectModel) {
        project.sheets.append(SheetModel(id: sheetId, name: name))
    }

    func serializeToPython() -> String {
        "proj.add_sheet(\(PythonLiteralEncoder.encodeString(name)), sheet_id=\(PythonLiteralEncoder.encodeString(sheetId)))"
    }
}

struct RenameSheetCommand: Command {
    let commandId: String
    let timestamp: Date
    let sheetId: String
    let name: String

    init(commandId: String = ModelID.make(),
         timestamp: Date = Date(),
         sheetId: String,
         name: String) {
        self.commandId = commandId
        self.timestamp = timestamp
        self.sheetId = sheetId
        self.name = name
    }

    func apply(to project: inout ProjectModel) {
        project.updateSheet(id: sheetId) { sheet in
            sheet.name = name
        }
    }

    func serializeToPython() -> String {
        "proj.rename_sheet(\(PythonLiteralEncoder.encodeString(sheetId)), name=\(PythonLiteralEncoder.encodeString(name)))"
    }
}

struct AddTableCommand: Command {
    let commandId: String
    let timestamp: Date
    let sheetId: String
    let tableId: String
    let name: String
    let rect: Rect
    let rows: Int
    let cols: Int
    let labels: LabelBands

    init(commandId: String = ModelID.make(),
         timestamp: Date = Date(),
         sheetId: String,
         tableId: String,
         name: String,
         rect: Rect,
         rows: Int,
         cols: Int,
         labels: LabelBands) {
        self.commandId = commandId
        self.timestamp = timestamp
        self.sheetId = sheetId
        self.tableId = tableId
        self.name = name
        self.rect = rect
        self.rows = rows
        self.cols = cols
        self.labels = labels
    }

    func apply(to project: inout ProjectModel) {
        project.updateSheet(id: sheetId) { sheet in
            let table = TableModel(id: tableId, name: name, rect: rect, rows: rows, cols: cols, labelBands: labels)
            sheet.tables.append(table)
        }
    }

    func serializeToPython() -> String {
        let x = PythonLiteralEncoder.encodeNumber(rect.x)
        let y = PythonLiteralEncoder.encodeNumber(rect.y)
        return "proj.add_table(\(PythonLiteralEncoder.encodeString(sheetId)), table_id=\(PythonLiteralEncoder.encodeString(tableId)), name=\(PythonLiteralEncoder.encodeString(name)), x=\(x), y=\(y), rows=\(rows), cols=\(cols), labels=\(PythonLiteralEncoder.encodeLabels(labels)))"
    }
}

struct SetTableRectCommand: Command {
    let commandId: String
    let timestamp: Date
    let tableId: String
    let rect: Rect

    init(commandId: String = ModelID.make(),
         timestamp: Date = Date(),
         tableId: String,
         rect: Rect) {
        self.commandId = commandId
        self.timestamp = timestamp
        self.tableId = tableId
        self.rect = rect
    }

    func apply(to project: inout ProjectModel) {
        project.updateTable(id: tableId) { table in
            table.rect = rect
        }
    }

    func serializeToPython() -> String {
        "proj.table(\(PythonLiteralEncoder.encodeString(tableId))).set_rect(\(PythonLiteralEncoder.encodeRect(rect)))"
    }
}

struct ResizeTableCommand: Command {
    let commandId: String
    let timestamp: Date
    let tableId: String
    let rows: Int?
    let cols: Int?

    init(commandId: String = ModelID.make(),
         timestamp: Date = Date(),
         tableId: String,
         rows: Int? = nil,
         cols: Int? = nil) {
        self.commandId = commandId
        self.timestamp = timestamp
        self.tableId = tableId
        self.rows = rows
        self.cols = cols
    }

    func apply(to project: inout ProjectModel) {
        project.updateTable(id: tableId) { table in
            if let rows {
                table.gridSpec.bodyRows = rows
            }
            if let cols {
                table.gridSpec.bodyCols = cols
            }
            table.normalizeColumnTypes()
        }
    }

    func serializeToPython() -> String {
        var args: [String] = []
        if let rows {
            args.append("rows=\(rows)")
        }
        if let cols {
            args.append("cols=\(cols)")
        }
        let joined = args.joined(separator: ", ")
        return "proj.table(\(PythonLiteralEncoder.encodeString(tableId))).resize(\(joined))"
    }
}

struct SetLabelBandsCommand: Command {
    let commandId: String
    let timestamp: Date
    let tableId: String
    let labelBands: LabelBands

    init(commandId: String = ModelID.make(),
         timestamp: Date = Date(),
         tableId: String,
         labelBands: LabelBands) {
        self.commandId = commandId
        self.timestamp = timestamp
        self.tableId = tableId
        self.labelBands = labelBands
    }

    func apply(to project: inout ProjectModel) {
        project.updateTable(id: tableId) { table in
            table.gridSpec.labelBands = labelBands
        }
    }

    func serializeToPython() -> String {
        "proj.table(\(PythonLiteralEncoder.encodeString(tableId))).set_labels(top=\(labelBands.topRows), left=\(labelBands.leftCols), bottom=\(labelBands.bottomRows), right=\(labelBands.rightCols))"
    }
}

struct SetCellsCommand: Command {
    let commandId: String
    let timestamp: Date
    let tableId: String
    let cellMap: [String: CellValue]

    init(commandId: String = ModelID.make(),
         timestamp: Date = Date(),
         tableId: String,
         cellMap: [String: CellValue]) {
        self.commandId = commandId
        self.timestamp = timestamp
        self.tableId = tableId
        self.cellMap = cellMap
    }

    func apply(to project: inout ProjectModel) {
        project.updateTable(id: tableId) { table in
            table.cellValues.merge(cellMap) { _, new in new }
            for (key, value) in cellMap {
                guard let parsed = try? RangeParser.parse(key),
                      parsed.region == .body else {
                    continue
                }
                table.updateColumnType(forBodyColumn: parsed.start.col, value: value)
            }
        }
    }

    func merged(with other: SetCellsCommand) -> SetCellsCommand? {
        guard tableId == other.tableId else {
            return nil
        }
        var merged = cellMap
        for (key, value) in other.cellMap {
            merged[key] = value
        }
        return SetCellsCommand(commandId: commandId, timestamp: timestamp, tableId: tableId, cellMap: merged)
    }

    func serializeToPython() -> String {
        var bodyAssignments: [(key: String, label: String, value: String)] = []
        var labelAssignments: [GridRegion: [(key: String, label: String, value: String)]] = [:]
        var otherCells: [String: CellValue] = [:]

        for (key, value) in cellMap {
            guard let parsed = try? RangeParser.parse(key),
                  parsed.start == parsed.end else {
                otherCells[key] = value
                continue
            }
            let label = RangeParser.cellLabel(row: parsed.start.row, col: parsed.start.col).lowercased()
            if parsed.region == .body {
                bodyAssignments.append((key: key, label: label, value: PythonLiteralEncoder.encode(value)))
                continue
            }
            labelAssignments[parsed.region, default: []].append(
                (key: key, label: label, value: PythonLiteralEncoder.encode(value))
            )
        }

        var lines: [String] = []
        if !bodyAssignments.isEmpty || !labelAssignments.isEmpty {
            lines.append("t = proj.table(\(PythonLiteralEncoder.encodeString(tableId)))")
        }
        if !bodyAssignments.isEmpty {
            lines.append("with table_context(t):")
            let sorted = bodyAssignments.sorted { $0.key < $1.key }
            for item in sorted {
                lines.append("    \(item.label) = \(item.value)")
            }
        }

        if !labelAssignments.isEmpty {
            let sortedRegions = labelAssignments.keys.sorted { $0.rawValue < $1.rawValue }
            for region in sortedRegions {
                lines.append("with label_context(t, \(PythonLiteralEncoder.encodeString(region.rawValue))):")
                let sorted = (labelAssignments[region] ?? []).sorted { $0.key < $1.key }
                for item in sorted {
                    lines.append("    \(item.label) = \(item.value)")
                }
            }
        }

        if !otherCells.isEmpty {
            lines.append("proj.table(\(PythonLiteralEncoder.encodeString(tableId))).set_cells(\(PythonLiteralEncoder.encodeDict(otherCells)))")
        }

        return lines.joined(separator: "\n")
    }
}

struct SetRangeCommand: Command {
    let commandId: String
    let timestamp: Date
    let tableId: String
    let range: String
    let values: [[CellValue]]
    let dtype: String?

    init(commandId: String = ModelID.make(),
         timestamp: Date = Date(),
         tableId: String,
         range: String,
         values: [[CellValue]],
         dtype: String? = nil) {
        self.commandId = commandId
        self.timestamp = timestamp
        self.tableId = tableId
        self.range = range
        self.values = values
        self.dtype = dtype
    }

    func apply(to project: inout ProjectModel) {
        project.updateTable(id: tableId) { table in
            table.rangeValues[range] = RangeValue(values: values, dtype: dtype)
            guard let parsed = try? RangeParser.parse(range) else {
                return
            }
            let startRow = parsed.start.row
            let startCol = parsed.start.col
            for (rowIndex, rowValues) in values.enumerated() {
                for (colIndex, value) in rowValues.enumerated() {
                    let row = startRow + rowIndex
                    let col = startCol + colIndex
                    let key = RangeParser.address(region: parsed.region, row: row, col: col)
                    table.cellValues[key] = value
                    if parsed.region == .body {
                        table.updateColumnType(forBodyColumn: col, value: value)
                    }
                }
            }
        }
    }

    func serializeToPython() -> String {
        var args = "\(PythonLiteralEncoder.encodeString(range)), \(PythonLiteralEncoder.encode2D(values))"
        if let dtype {
            args += ", dtype=\(PythonLiteralEncoder.encodeString(dtype))"
        }
        return "proj.table(\(PythonLiteralEncoder.encodeString(tableId))).set_range(\(args))"
    }
}

struct SetLabelBandCommand: Command {
    let commandId: String
    let timestamp: Date
    let tableId: String
    let band: LabelBandPosition
    let index: Int
    let values: [String]

    init(commandId: String = ModelID.make(),
         timestamp: Date = Date(),
         tableId: String,
         band: LabelBandPosition,
         index: Int,
         values: [String]) {
        self.commandId = commandId
        self.timestamp = timestamp
        self.tableId = tableId
        self.band = band
        self.index = index
        self.values = values
    }

    func apply(to project: inout ProjectModel) {
        project.updateTable(id: tableId) { table in
            table.labelBandValues.set(band: band, index: index, values: values)
        }
    }

    func serializeToPython() -> String {
        "proj.table(\(PythonLiteralEncoder.encodeString(tableId))).set_label_band(\(PythonLiteralEncoder.encodeString(band.rawValue)), index=\(index), values=\(PythonLiteralEncoder.encodeStringList(values)))"
    }
}

struct SetFormulaCommand: Command {
    let commandId: String
    let timestamp: Date
    let tableId: String
    let targetRange: String
    let formula: String
    let mode: FormulaMode

    init(commandId: String = ModelID.make(),
         timestamp: Date = Date(),
         tableId: String,
         targetRange: String,
         formula: String,
         mode: FormulaMode = .spreadsheet) {
        self.commandId = commandId
        self.timestamp = timestamp
        self.tableId = tableId
        self.targetRange = targetRange
        self.formula = formula
        self.mode = mode
    }

    func apply(to project: inout ProjectModel) {
        project.updateTable(id: tableId) { table in
            let trimmed = formula.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                table.formulas.removeValue(forKey: targetRange)
                return
            }
            table.formulas[targetRange] = FormulaSpec(formula: trimmed, mode: mode)
            if let range = try? RangeParser.parse(targetRange) {
                let rowStart = min(range.start.row, range.end.row)
                let rowEnd = max(range.start.row, range.end.row)
                let colStart = min(range.start.col, range.end.col)
                let colEnd = max(range.start.col, range.end.col)
                for row in rowStart...rowEnd {
                    for col in colStart...colEnd {
                        let key = RangeParser.address(region: range.region, row: row, col: col)
                        table.cellValues.removeValue(forKey: key)
                    }
                }
            } else {
                table.cellValues.removeValue(forKey: targetRange)
            }
        }
    }

    func serializeToPython() -> String {
        let trimmed = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let empty = PythonLiteralEncoder.encodeString("")
            return "proj.table(\(PythonLiteralEncoder.encodeString(tableId))).set_formula(\(PythonLiteralEncoder.encodeString(targetRange)), \(empty), mode=\(PythonLiteralEncoder.encodeString(mode.rawValue)))"
        }

        guard mode == .spreadsheet,
              let parsed = try? RangeParser.parse(targetRange),
              parsed.start == parsed.end else {
            return "proj.table(\(PythonLiteralEncoder.encodeString(tableId))).set_formula(\(PythonLiteralEncoder.encodeString(targetRange)), \(PythonLiteralEncoder.encodeString(formula)), mode=\(PythonLiteralEncoder.encodeString(mode.rawValue)))"
        }

        let cellLabel = RangeParser.cellLabel(row: parsed.start.row, col: parsed.start.col).lowercased()
        let formulaBody = trimmed.hasPrefix("=") ? String(trimmed.dropFirst()) : trimmed
        let helperExpression = FormulaPythonSerializer.aggregateHelperExpression(formulaBody)
        let useInline = FormulaPythonSerializer.isSimpleExpression(formulaBody)
        let assignment: String
        if let helperExpression {
            assignment = "\(cellLabel) = \(helperExpression)"
        } else if useInline {
            assignment = "\(cellLabel) = \(FormulaPythonSerializer.normalizeExpression(formulaBody))"
        } else {
            let pythonic = FormulaPythonSerializer.pythonicAggregates(formulaBody)
            assignment = "\(cellLabel) = formula(\(PythonLiteralEncoder.encodeString(pythonic)))"
        }
        let assignmentTarget: String
        if parsed.region == .body {
            assignmentTarget = assignment
        } else {
            assignmentTarget = "\(parsed.region.rawValue).\(assignment)"
        }
        let tableLine = "t = proj.table(\(PythonLiteralEncoder.encodeString(tableId)))"
        return [
            tableLine,
            "with table_context(t):",
            "    \(assignmentTarget)"
        ].joined(separator: "\n")
    }
}

private enum FormulaPythonSerializer {
    static func isSimpleExpression(_ formula: String) -> Bool {
        let trimmed = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        if trimmed.contains("$") || trimmed.contains(",") {
            return false
        }
        if trimmed.contains("^") {
            return false
        }
        let functionPattern = #"[A-Za-z_][A-Za-z0-9_]*\s*\("#
        if trimmed.range(of: functionPattern, options: .regularExpression) != nil {
            return false
        }
        if trimmed.contains(":") {
            return false
        }
        let allowedPattern = #"^[a-z0-9_\.\+\-\*/\s]+$"#
        return trimmed.lowercased().range(of: allowedPattern, options: .regularExpression) != nil
    }

    static func normalizeExpression(_ formula: String) -> String {
        formula.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func pythonicAggregates(_ formula: String) -> String {
        var result = formula
        let replacements: [(pattern: String, replacement: String)] = [
            ("(?i)(?<!\\.)SUM\\s*\\(", "np.sum("),
            ("(?i)(?<!\\.)AVERAGE\\s*\\(", "np.mean("),
            ("(?i)(?<!\\.)MIN\\s*\\(", "np.min("),
            ("(?i)(?<!\\.)MAX\\s*\\(", "np.max(")
        ]
        for (pattern, replacement) in replacements {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
            }
        }
        return result
    }

    static func aggregateHelperExpression(_ formula: String) -> String? {
        let trimmed = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let (name, args) = parseFunctionCall(trimmed), !args.isEmpty else {
            return nil
        }
        guard let helper = helperName(for: name) else {
            return nil
        }
        var encodedArgs: [String] = []
        for arg in args {
            let normalized = arg.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard isAggregateArgument(normalized) else {
                return nil
            }
            encodedArgs.append(PythonLiteralEncoder.encodeString(normalized))
        }
        guard !encodedArgs.isEmpty else {
            return nil
        }
        return "\(helper)(\(encodedArgs.joined(separator: ", ")))"
    }

    private static func parseFunctionCall(_ formula: String) -> (name: String, args: [String])? {
        guard let openIndex = formula.firstIndex(of: "("),
              formula.hasSuffix(")") else {
            return nil
        }
        let name = String(formula[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return nil
        }
        let innerStart = formula.index(after: openIndex)
        let innerEnd = formula.index(before: formula.endIndex)
        let inner = String(formula[innerStart..<innerEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inner.isEmpty else {
            return nil
        }
        var args: [String] = []
        var current = ""
        var depth = 0
        for ch in inner {
            if ch == "(" {
                depth += 1
                current.append(ch)
                continue
            }
            if ch == ")" {
                depth -= 1
                guard depth >= 0 else {
                    return nil
                }
                current.append(ch)
                continue
            }
            if ch == "," && depth == 0 {
                args.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        if depth != 0 {
            return nil
        }
        if !current.isEmpty {
            args.append(current)
        }
        return (name, args)
    }

    private static func helperName(for function: String) -> String? {
        switch function.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "SUM":
            return "c_sum"
        case "AVERAGE":
            return "c_avg"
        case "MIN":
            return "c_min"
        case "MAX":
            return "c_max"
        case "COUNT":
            return "c_count"
        case "COUNTA":
            return "c_counta"
        default:
            return nil
        }
    }

    private static func isAggregateArgument(_ arg: String) -> Bool {
        let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        if trimmed.range(of: #"^[+-]?\d+(\.\d+)?$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.contains(where: { "+-*/^".contains($0) }) {
            return false
        }
        let pattern = #"^[A-Za-z0-9_\$\[\]:\.\(\)]+$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}

struct InsertRowsCommand: Command {
    let commandId: String
    let timestamp: Date
    let tableId: String
    let at: Int
    let count: Int

    init(commandId: String = ModelID.make(),
         timestamp: Date = Date(),
         tableId: String,
         at: Int,
         count: Int) {
        self.commandId = commandId
        self.timestamp = timestamp
        self.tableId = tableId
        self.at = at
        self.count = count
    }

    func apply(to project: inout ProjectModel) {
        project.updateTable(id: tableId) { table in
            table.gridSpec.bodyRows += count
        }
    }

    func serializeToPython() -> String {
        "proj.table(\(PythonLiteralEncoder.encodeString(tableId))).insert_rows(at=\(at), count=\(count))"
    }
}

struct InsertColsCommand: Command {
    let commandId: String
    let timestamp: Date
    let tableId: String
    let at: Int
    let count: Int

    init(commandId: String = ModelID.make(),
         timestamp: Date = Date(),
         tableId: String,
         at: Int,
         count: Int) {
        self.commandId = commandId
        self.timestamp = timestamp
        self.tableId = tableId
        self.at = at
        self.count = count
    }

    func apply(to project: inout ProjectModel) {
        project.updateTable(id: tableId) { table in
            table.gridSpec.bodyCols += count
            table.normalizeColumnTypes()
        }
    }

    func serializeToPython() -> String {
        "proj.table(\(PythonLiteralEncoder.encodeString(tableId))).insert_cols(at=\(at), count=\(count))"
    }
}
