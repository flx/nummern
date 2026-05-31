"""Serialization to/from the JSON contract the Swift app consumes.

The body travels column-oriented with an explicit dtype per column, so the app
can render typed values without guessing. Empty cells are ``null``.
"""

from __future__ import annotations

import datetime as _dt
import math
from typing import Any, Dict, List

import numpy as np
import pandas as pd

from .geometry import LabelBands, Rect
from .project import Project, Sheet
from .table import Table

__all__ = ["to_dict", "to_json", "from_dict"]


def _encode_scalar(value: Any) -> Any:
    if value is None or value is pd.NA:
        return None
    if isinstance(value, float) and math.isnan(value):
        return None
    if isinstance(value, np.generic):
        value = value.item()
    if isinstance(value, (pd.Timestamp, _dt.datetime)):
        return value.isoformat()
    if isinstance(value, _dt.date):
        return value.isoformat()
    if isinstance(value, _dt.time):
        return value.strftime("%H:%M:%S")
    if isinstance(value, float) and value.is_integer():
        return value
    return value


def _dtype_name(series: pd.Series) -> str:
    kind = series.convert_dtypes().dtype
    name = str(kind).lower()
    if "int" in name or "float" in name:
        return "number"
    if "bool" in name:
        return "bool"
    if "datetime" in name:
        return "datetime"
    if "string" in name:
        return "string"
    return "string" if name == "object" else name


def _encode_table(table: Table) -> Dict[str, Any]:
    df = table.df
    columns: List[Dict[str, Any]] = []
    data: List[List[Any]] = []
    headers = table.header_names()
    for c in range(table.body_cols):
        series = df.iloc[:, c]
        columns.append({
            "index": c,
            "name": headers[c],
            "dtype": _dtype_name(series),
            "format": table.column_types.get(c),
        })
        data.append([_encode_scalar(v) for v in series.tolist()])
    payload: Dict[str, Any] = {
        "id": table.id,
        "name": table.name,
        "rect": table.rect.to_dict(),
        "grid": {
            "rows": table.body_rows,
            "cols": table.body_cols,
            "labels": table.bands.to_dict(),
        },
        "columns": columns,
        # column-oriented body: data[col][row]
        "body": data,
        "labels": {region: table._band_grid(region) for region in ("top", "left", "bottom", "right")},
    }
    summary = getattr(table, "summary_spec", None)
    if summary is not None:
        payload["summary"] = summary.to_dict()
    return payload


def to_dict(project: Project) -> Dict[str, Any]:
    from .charts import ChartSpec  # local import to avoid cycle

    sheets = []
    for sheet in project.sheets:
        sheets.append({
            "id": sheet.id,
            "name": sheet.name,
            "tables": [_encode_table(t) for t in sheet.tables],
            "charts": [c.to_dict() for c in sheet.charts if isinstance(c, ChartSpec)],
        })
    return {"version": 1, "sheets": sheets}


def to_json(project: Project, **kwargs: Any) -> str:
    import json

    return json.dumps(to_dict(project), separators=(",", ":"), **kwargs)


def from_dict(data: Dict[str, Any]) -> Project:
    """Rebuild a project from :func:`to_dict` output (used by tests/snapshots)."""
    from .charts import ChartSpec

    proj = Project()
    for sheet_data in data.get("sheets", []):
        sheet = proj.add_sheet(sheet_data.get("name"), id=sheet_data["id"])
        for table_data in sheet_data.get("tables", []):
            grid = table_data.get("grid", {})
            bands = LabelBands.from_dict(grid.get("labels"))
            table = proj.add_table(
                sheet, id=table_data["id"], name=table_data.get("name"),
                rows=grid.get("rows", 0), cols=grid.get("cols", 0),
                rect=table_data.get("rect"),
            )
            table.bands = bands
            # restore body (column-oriented: body[col][row])
            body = table_data.get("body", [])
            for c, col_values in enumerate(body):
                for r, value in enumerate(col_values):
                    if value is not None:
                        table[f"{_col_letter(c)}{r}"] = value
            # restore label bands
            for region, grid_vals in (table_data.get("labels") or {}).items():
                table._labels[region] = [list(row) for row in grid_vals]
            for col in table_data.get("columns", []):
                fmt = col.get("format")
                if fmt:
                    table.column_types[col["index"]] = fmt
            table.sync_rect_size()
        for chart_data in sheet_data.get("charts", []):
            sheet.charts.append(ChartSpec.from_dict(chart_data))
    return proj


def _col_letter(index: int) -> str:
    from .address import column_label

    return column_label(index)
