import Foundation

struct AddSheetCommand: Command {
    let commandId: String
    let timestamp: Date
    let name: String
    let sheetId: String

    init(commandId: String = ModelID.make(),
         timestamp: Date = Date(),
         name: String,
         sheetId: String = ModelID.make()) {
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
         tableId: String = ModelID.make(),
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
        "proj.add_table(\(PythonLiteralEncoder.encodeString(sheetId)), table_id=\(PythonLiteralEncoder.encodeString(tableId)), name=\(PythonLiteralEncoder.encodeString(name)), rect=\(PythonLiteralEncoder.encodeRect(rect)), rows=\(rows), cols=\(cols), labels=\(PythonLiteralEncoder.encodeLabels(labels)))"
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
        "proj.table(\(PythonLiteralEncoder.encodeString(tableId))).set_cells(\(PythonLiteralEncoder.encodeDict(cellMap)))"
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
            table.formulas[targetRange] = FormulaSpec(formula: formula, mode: mode)
        }
    }

    func serializeToPython() -> String {
        "proj.table(\(PythonLiteralEncoder.encodeString(tableId))).set_formula(\(PythonLiteralEncoder.encodeString(targetRange)), \(PythonLiteralEncoder.encodeString(formula)), mode=\(PythonLiteralEncoder.encodeString(mode.rawValue)))"
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
        }
    }

    func serializeToPython() -> String {
        "proj.table(\(PythonLiteralEncoder.encodeString(tableId))).insert_cols(at=\(at), count=\(count))"
    }
}
