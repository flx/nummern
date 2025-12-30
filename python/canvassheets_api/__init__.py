from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple


class RangeParserError(ValueError):
    pass


def column_index(label: str) -> int:
    upper = label.strip().upper()
    if not upper:
        raise RangeParserError("Invalid column label")
    value = 0
    for ch in upper:
        if ch < "A" or ch > "Z":
            raise RangeParserError("Invalid column label")
        value = value * 26 + (ord(ch) - ord("A") + 1)
    return value - 1


def column_label(index: int) -> str:
    if index < 0:
        raise RangeParserError("Column index must be non-negative")
    number = index + 1
    chars: List[str] = []
    while number > 0:
        remainder = (number - 1) % 26
        chars.append(chr(ord("A") + remainder))
        number = (number - 1) // 26
    return "".join(reversed(chars))


def parse_cell(cell: str) -> Tuple[int, int]:
    trimmed = cell.strip()
    if not trimmed:
        raise RangeParserError("Invalid cell reference")
    letters = ""
    numbers = ""
    for ch in trimmed:
        if ch.isalpha() and not numbers:
            letters += ch
        else:
            numbers += ch
    if not letters or not numbers:
        raise RangeParserError("Invalid cell reference")
    if not numbers.isdigit():
        raise RangeParserError("Invalid cell reference")
    row_number = int(numbers)
    if row_number <= 0:
        raise RangeParserError("Invalid cell reference")
    col_index = column_index(letters)
    return row_number - 1, col_index


def cell_label(row: int, col: int) -> str:
    return f"{column_label(col)}{row + 1}"


def address(region: str, row: int, col: int) -> str:
    return f"{region}[{cell_label(row, col)}]"


def parse_range(range_str: str) -> Tuple[str, int, int, int, int]:
    trimmed = range_str.strip()
    if "[" not in trimmed or not trimmed.endswith("]"):
        raise RangeParserError("Invalid range format")
    region, inner = trimmed.split("[", 1)
    region = region.strip()
    inner = inner[:-1]
    if not region:
        raise RangeParserError("Invalid region")
    parts = inner.split(":")
    if len(parts) == 1:
        start_row, start_col = parse_cell(parts[0])
        return region, start_row, start_col, start_row, start_col
    if len(parts) == 2:
        start_row, start_col = parse_cell(parts[0])
        end_row, end_col = parse_cell(parts[1])
        return region, start_row, start_col, end_row, end_col
    raise RangeParserError("Invalid range format")


def _cell_value_to_json(value: Any) -> Dict[str, Any]:
    if isinstance(value, dict) and "type" in value:
        return value
    if value is None:
        return {"type": "empty"}
    if isinstance(value, bool):
        return {"type": "bool", "value": value}
    if isinstance(value, (int, float)):
        return {"type": "number", "value": float(value)}
    return {"type": "string", "value": str(value)}


@dataclass
class Rect:
    x: float
    y: float
    width: float
    height: float

    @staticmethod
    def from_value(value: Any) -> "Rect":
        if isinstance(value, Rect):
            return value
        if isinstance(value, (list, tuple)) and len(value) == 4:
            return Rect(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
        if isinstance(value, dict):
            return Rect(float(value["x"]), float(value["y"]), float(value["width"]), float(value["height"]))
        raise TypeError("Invalid rect value")

    def to_dict(self) -> Dict[str, Any]:
        return {"x": self.x, "y": self.y, "width": self.width, "height": self.height}


@dataclass
class LabelBands:
    topRows: int
    bottomRows: int
    leftCols: int
    rightCols: int

    @staticmethod
    def zero() -> "LabelBands":
        return LabelBands(topRows=0, bottomRows=0, leftCols=0, rightCols=0)

    @staticmethod
    def from_labels(labels: Optional[Dict[str, Any]]) -> "LabelBands":
        if not labels:
            return LabelBands.zero()
        return LabelBands(
            topRows=int(labels.get("top", 0)),
            bottomRows=int(labels.get("bottom", 0)),
            leftCols=int(labels.get("left", 0)),
            rightCols=int(labels.get("right", 0)),
        )

    def to_dict(self) -> Dict[str, Any]:
        return {
            "topRows": self.topRows,
            "bottomRows": self.bottomRows,
            "leftCols": self.leftCols,
            "rightCols": self.rightCols,
        }


@dataclass
class GridSpec:
    bodyRows: int
    bodyCols: int
    labelBands: LabelBands = field(default_factory=LabelBands.zero)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "bodyRows": self.bodyRows,
            "bodyCols": self.bodyCols,
            "labelBands": self.labelBands.to_dict(),
        }


@dataclass
class Table:
    id: str
    name: str
    rect: Rect
    grid_spec: GridSpec
    cell_values: Dict[str, Any] = field(default_factory=dict)
    range_values: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    formulas: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    label_band_values: Dict[str, Dict[str, List[str]]] = field(
        default_factory=lambda: {"top": {}, "bottom": {}, "left": {}, "right": {}}
    )

    def set_rect(self, rect: Any) -> None:
        self.rect = Rect.from_value(rect)

    def resize(self, rows: Optional[int] = None, cols: Optional[int] = None) -> None:
        if rows is not None:
            self.grid_spec.bodyRows = int(rows)
        if cols is not None:
            self.grid_spec.bodyCols = int(cols)

    def set_labels(self, top: Optional[int] = None, left: Optional[int] = None,
                   bottom: Optional[int] = None, right: Optional[int] = None) -> None:
        if top is not None:
            self.grid_spec.labelBands.topRows = int(top)
        if left is not None:
            self.grid_spec.labelBands.leftCols = int(left)
        if bottom is not None:
            self.grid_spec.labelBands.bottomRows = int(bottom)
        if right is not None:
            self.grid_spec.labelBands.rightCols = int(right)

    def set_cells(self, mapping: Dict[str, Any]) -> None:
        for key, value in mapping.items():
            self.cell_values[key] = value

    def set_range(self, range_str: str, values: List[List[Any]], dtype: Optional[str] = None) -> None:
        self.range_values[range_str] = {"values": values, "dtype": dtype}
        try:
            region, start_row, start_col, _, _ = parse_range(range_str)
        except RangeParserError:
            return
        for row_index, row_values in enumerate(values):
            for col_index, value in enumerate(row_values):
                row = start_row + row_index
                col = start_col + col_index
                key = address(region, row, col)
                self.cell_values[key] = value

    def set_label_band(self, band: str, index: int, values: List[str]) -> None:
        target = self.label_band_values.get(band)
        if target is None:
            raise ValueError(f"Unknown label band: {band}")
        target[str(index)] = list(values)

    def set_formula(self, target_range: str, formula: str, mode: str = "spreadsheet") -> None:
        self.formulas[target_range] = {"formula": formula, "mode": mode}

    def insert_rows(self, at: int, count: int) -> None:
        self.grid_spec.bodyRows += int(count)

    def insert_cols(self, at: int, count: int) -> None:
        self.grid_spec.bodyCols += int(count)

    def _encode_cell_values(self) -> Dict[str, Any]:
        return {key: _cell_value_to_json(value) for key, value in self.cell_values.items()}

    def _encode_range_values(self) -> Dict[str, Any]:
        encoded: Dict[str, Any] = {}
        for key, payload in self.range_values.items():
            values = payload.get("values", [])
            dtype = payload.get("dtype")
            encoded_values = [[_cell_value_to_json(value) for value in row] for row in values]
            encoded[key] = {"values": encoded_values, "dtype": dtype}
        return encoded

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "rect": self.rect.to_dict(),
            "gridSpec": self.grid_spec.to_dict(),
            "cellValues": self._encode_cell_values(),
            "rangeValues": self._encode_range_values(),
            "formulas": self.formulas,
            "labelBandValues": self.label_band_values,
        }


@dataclass
class Sheet:
    id: str
    name: str
    tables: List[Table] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {"id": self.id, "name": self.name, "tables": [table.to_dict() for table in self.tables]}


class Project:
    def __init__(self) -> None:
        self.sheets: List[Sheet] = []

    def add_sheet(self, name: str, sheet_id: str) -> Sheet:
        sheet = Sheet(id=sheet_id, name=name)
        self.sheets.append(sheet)
        return sheet

    def add_table(self, sheet_id: str, table_id: str, name: str,
                  rect: Any, rows: int, cols: int, labels: Optional[Dict[str, Any]] = None) -> Table:
        sheet = self._find_sheet(sheet_id)
        if sheet is None:
            raise KeyError(f"Unknown sheet_id: {sheet_id}")
        rect_value = Rect.from_value(rect)
        bands = LabelBands.from_labels(labels)
        grid_spec = GridSpec(bodyRows=int(rows), bodyCols=int(cols), labelBands=bands)
        table = Table(id=table_id, name=name, rect=rect_value, grid_spec=grid_spec)
        sheet.tables.append(table)
        return table

    def table(self, table_id: str) -> Table:
        for sheet in self.sheets:
            for table in sheet.tables:
                if table.id == table_id:
                    return table
        raise KeyError(f"Unknown table_id: {table_id}")

    def to_dict(self) -> Dict[str, Any]:
        return {"sheets": [sheet.to_dict() for sheet in self.sheets]}

    def _find_sheet(self, sheet_id: str) -> Optional[Sheet]:
        for sheet in self.sheets:
            if sheet.id == sheet_id:
                return sheet
        return None


__all__ = [
    "Project",
    "Table",
    "Rect",
    "GridSpec",
    "LabelBands",
    "RangeParserError",
    "address",
    "parse_range",
    "column_label",
    "column_index",
]
