"""Portable export of a computed project.

Because a recorded script is already plain, runnable Python, the most portable
"formula-aware" artifact is the script itself. These helpers additionally emit a
dependency-free snapshot of the *computed* values:

  * ``export_numpy_script`` -> ``tables = {id: {"body": np.array(...), "labels": {...}}}``
  * ``export_matplotlib_script`` -> the numpy snapshot plus matplotlib plotting code
"""

from __future__ import annotations

import datetime as _dt
import math
from pprint import pformat
from typing import Any, Dict, List

import numpy as np
import pandas as pd

from .address import column_label
from .charts import ChartSpec
from .project import Project
from .table import Table

__all__ = ["export_numpy_script", "export_matplotlib_script"]


def _scalar(value: Any) -> Any:
    if value is None or value is pd.NA:
        return None
    if isinstance(value, float) and math.isnan(value):
        return None
    if isinstance(value, np.generic):
        value = value.item()
    if isinstance(value, (pd.Timestamp, _dt.datetime, _dt.date)):
        return value.isoformat()
    return value


def _body_values(table: Table) -> List[List[Any]]:
    rows = []
    for r in range(table.body_rows):
        rows.append([_scalar(table.df.iat[r, c]) for c in range(table.body_cols)])
    return rows


def _coerce(values: List[List[Any]]):
    flat = [v for row in values for v in row]
    numeric = all(v is None or isinstance(v, (int, float)) and not isinstance(v, bool) for v in flat)
    if numeric and flat:
        coerced = [[float("nan") if v is None else float(v) for v in row] for row in values]
        return coerced, "float"
    return values, "object"


def _labels(table: Table, include_labels: bool) -> Dict[str, Any]:
    if not include_labels:
        return {}
    out = {}
    for region in ("top", "left", "bottom", "right"):
        rows, cols = table.bands.shape_for(region, table.body_rows, table.body_cols)
        if rows > 0 and cols > 0:
            out[region] = table._band_grid(region)
    return out


def export_numpy_script(project: Project, include_labels: bool = True,
                        include_formulas: bool = False) -> str:
    lines = [
        "import numpy as np",
        "",
        "# Computed snapshot exported by canvassheets.",
        "# The original script.py remains the portable, formula-aware source.",
        "",
        "tables = {}",
    ]
    for table in project.tables():
        values, dtype = _coerce(_body_values(table))
        body_literal = pformat(values, width=88)
        lines.append(f"tables[{table.id!r}] = {{")
        lines.append(f"    'body': np.array({body_literal}, dtype={dtype}),")
        labels = _labels(table, include_labels)
        if labels:
            lines.append(f"    'labels': {pformat(labels, width=88)},")
        lines.append("}")
        lines.append("")
    return "\n".join(lines)


def export_matplotlib_script(project: Project) -> str:
    lines = [export_numpy_script(project, include_labels=True), ""]
    lines.append("import matplotlib.pyplot as plt")
    lines.append("")
    charts = [(s, c) for s in project.sheets for c in s.charts if isinstance(c, ChartSpec)]
    if not charts:
        lines.append("# (no charts defined)")
        return "\n".join(lines)
    for _, chart in charts:
        lines.extend(_chart_block(project, chart))
    lines.append("plt.show()")
    return "\n".join(lines)


def _chart_block(project: Project, chart: ChartSpec) -> List[str]:
    from .address import parse_range

    table = project.table(chart.table_id)
    ref = chart.value_range
    if "[" in ref and ref.endswith("]"):
        ref = ref[ref.index("[") + 1:-1]
    r0, c0, r1, c1 = parse_range(ref)
    block = [[_scalar(table.df.iat[r, c]) for c in range(c0, c1 + 1)] for r in range(r0, r1 + 1)]
    arr = pformat(block, width=88)
    title = chart.title or chart.name
    out = [
        f"# chart {chart.id}: {chart.chart_type}",
        "fig, ax = plt.subplots()",
        f"_data = np.array({arr}, dtype=object)",
    ]
    if chart.chart_type == "pie":
        out.append("ax.pie([float(v) for v in _data[:, 0]])")
    elif chart.chart_type == "bar":
        out.append("for j in range(_data.shape[1]):")
        out.append("    ax.bar(np.arange(_data.shape[0]) + j*0.1, [float(v) for v in _data[:, j]], width=0.1)")
    else:  # line
        out.append("for j in range(_data.shape[1]):")
        out.append("    ax.plot([float(v) for v in _data[:, j]])")
    out.append(f"ax.set_title({title!r})")
    out.append("")
    return out
