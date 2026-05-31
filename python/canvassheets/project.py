"""``Project`` and ``Sheet`` — the document root.

A script builds a project with explicit, ordinary Python calls::

    from canvassheets import Project
    proj = Project()
    s = proj.add_sheet("Tab1")
    t = proj.add_table(s, rows=20, cols=6)
    t['B0:E19'] = data
    t['F'] = t['B'] + t['C'] + t['D'] + t['E']   # a "formula" is just Python
    proj.run()                                    # materialize summaries/charts

The same file runs under plain ``python script.py``; there is no exec harness.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Union

from .geometry import CELL_HEIGHT, CELL_WIDTH, LabelBands, Rect
from .table import Table

__all__ = ["Project", "Sheet"]

_DEFAULT_ORIGIN = 80.0
_DEFAULT_OFFSET = 24.0


class Sheet:
    def __init__(self, id: str, name: str) -> None:
        self.id = id
        self.name = name
        self.tables: List[Table] = []
        self.charts: List["Any"] = []  # charts.ChartSpec, added in P5

    def __repr__(self) -> str:  # pragma: no cover
        return f"Sheet(id={self.id!r}, tables={len(self.tables)})"


class Project:
    def __init__(self) -> None:
        self.sheets: List[Sheet] = []
        self._seq: Dict[str, int] = {"sheet": 0, "table": 0, "chart": 0}

    # -- id helpers ---------------------------------------------------------
    def _next_id(self, kind: str) -> str:
        self._seq[kind] += 1
        return f"{kind}_{self._seq[kind]}"

    def _observe_id(self, kind: str, given: str) -> None:
        """Keep the auto-counter ahead of any explicit id like ``table_7``."""
        prefix = f"{kind}_"
        if given.startswith(prefix):
            suffix = given[len(prefix):]
            if suffix.isdigit():
                self._seq[kind] = max(self._seq[kind], int(suffix))

    # -- sheets -------------------------------------------------------------
    def add_sheet(self, name: Optional[str] = None, id: Optional[str] = None) -> Sheet:
        sheet_id = id or self._next_id("sheet")
        if id is not None:
            self._observe_id("sheet", id)
        if self._find_sheet(sheet_id) is not None:
            raise ValueError(f"Duplicate sheet id: {sheet_id}")
        sheet = Sheet(sheet_id, name or sheet_id)
        self.sheets.append(sheet)
        return sheet

    def rename_sheet(self, sheet: Union[str, Sheet], name: str) -> Sheet:
        target = self.sheet(sheet) if isinstance(sheet, str) else sheet
        target.name = name
        return target

    # -- tables -------------------------------------------------------------
    def add_table(self, sheet: Union[str, Sheet], id: Optional[str] = None,
                  name: Optional[str] = None, *, rows: int = 10, cols: int = 6,
                  labels: Optional[Dict[str, int]] = None,
                  x: Optional[float] = None, y: Optional[float] = None,
                  rect: Optional[Any] = None) -> Table:
        owner = self.sheet(sheet) if isinstance(sheet, str) else sheet
        table_id = id or self._next_id("table")
        if id is not None:
            self._observe_id("table", id)
        if self._find_table(table_id) is not None:
            raise ValueError(f"Duplicate table id: {table_id}")
        bands = LabelBands.from_dict(labels)
        rect_value = Rect.from_dict(rect) if rect is not None else self._default_rect(x, y)
        table = Table(table_id, name, rows=rows, cols=cols, bands=bands, rect=rect_value)
        owner.tables.append(table)
        return table

    def _default_rect(self, x: Optional[float], y: Optional[float]) -> Rect:
        count = sum(len(s.tables) + len(s.charts) for s in self.sheets)
        offset = count * _DEFAULT_OFFSET
        return Rect(
            _DEFAULT_ORIGIN + offset if x is None else float(x),
            _DEFAULT_ORIGIN + offset if y is None else float(y),
            0.0, 0.0,
        )

    # -- summaries & charts (lazy imports avoid cycles) ---------------------
    def add_summary(self, sheet: Union[str, Sheet], source: Union[str, Any], group_by: Any,
                    values: Any, *, source_range: Optional[str] = None,
                    id: Optional[str] = None, name: Optional[str] = None,
                    x: Optional[float] = None, y: Optional[float] = None) -> Any:
        from .summary import add_summary as _add_summary

        return _add_summary(self, sheet, source, group_by, values,
                            source_range=source_range, id=id, name=name, x=x, y=y)

    def add_chart(self, sheet: Union[str, Sheet], chart_type: str, table: Union[str, Any],
                  value_range: str, *, label_range: Optional[str] = None,
                  id: Optional[str] = None, name: Optional[str] = None,
                  title: str = "", x_axis_title: str = "", y_axis_title: str = "",
                  show_legend: bool = True, x: Optional[float] = None,
                  y: Optional[float] = None) -> Any:
        from .charts import ChartSpec
        from .geometry import Rect

        owner = self.sheet(sheet) if isinstance(sheet, str) else sheet
        table_id = table if isinstance(table, str) else table.id
        self.table(table_id)  # validate
        chart_id = id or self._next_id("chart")
        if id is not None:
            self._observe_id("chart", id)
        rect = Rect(_DEFAULT_ORIGIN if x is None else float(x),
                    _DEFAULT_ORIGIN if y is None else float(y), 360.0, 240.0)
        chart = ChartSpec(id=chart_id, name=name or chart_id, chart_type=chart_type,
                          table_id=table_id, value_range=value_range, label_range=label_range,
                          title=title, x_axis_title=x_axis_title, y_axis_title=y_axis_title,
                          show_legend=show_legend, rect=rect)
        owner.charts.append(chart)
        return chart

    # -- lookups ------------------------------------------------------------
    def sheet(self, sheet_id: str) -> Sheet:
        found = self._find_sheet(sheet_id)
        if found is None:
            raise KeyError(f"Unknown sheet id: {sheet_id}")
        return found

    def table(self, table_id: str) -> Table:
        found = self._find_table(table_id)
        if found is None:
            raise KeyError(f"Unknown table id: {table_id}")
        return found

    def _find_sheet(self, sheet_id: str) -> Optional[Sheet]:
        return next((s for s in self.sheets if s.id == sheet_id), None)

    def _find_table(self, table_id: str) -> Optional[Table]:
        for sheet in self.sheets:
            for table in sheet.tables:
                if table.id == table_id:
                    return table
        return None

    def _sheet_of_table(self, table_id: str) -> Optional[Sheet]:
        for sheet in self.sheets:
            if any(t.id == table_id for t in sheet.tables):
                return sheet
        return None

    def tables(self) -> List[Table]:
        return [t for s in self.sheets for t in s.tables]

    # -- materialization ----------------------------------------------------
    def run(self) -> "Project":
        """Recompute derived objects (summaries, chart caches).

        Plain data and derived-column statements have already executed in script
        order; this refreshes objects that depend on a *post-run* view of their
        sources. Idempotent.
        """
        for table in self.tables():
            recompute = getattr(table, "recompute", None)
            if callable(recompute):
                recompute(self)
        return self
