"""The ``Table`` — a pandas-backed spreadsheet table.

The body is a real ``pandas.DataFrame`` stored positionally (a ``RangeIndex`` on
both axes). Indexing sugar (``t['A0']``, ``t['A']``, ``t['A0:C9']``) maps to
``iloc``/``iat`` so it is unambiguous and never collides with column labels.

There is no formula language here: a "formula" is just an ordinary Python
statement such as ``t['F'] = t['B'] + t['C']``. The RHS is evaluated by pandas
and the computed values are stored. Whether a cell was authored as a literal or
an expression is the *app's* concern (its command log), not the library's — which
is what keeps recorded scripts plain, runnable Python.

Graduation to pandas: ``table.to_pandas(named=True)`` returns a copy with column
names taken from the top label row and typed columns.
"""

from __future__ import annotations

import datetime as _dt
import math
from typing import Any, Dict, Iterable, List, Optional

import numpy as np
import pandas as pd

from . import address as _addr
from .address import CellRef, ColRangeRef, ColRef, NameRef, RangeRef
from .geometry import CELL_HEIGHT, CELL_WIDTH, LabelBands, Rect

__all__ = ["Table", "BandProxy"]

_REGIONS = ("top", "left", "bottom", "right")
# Per-column display types (README §7.1). The stored value stays native;
# the type is display/format metadata handed to the app.
COLUMN_TYPES = {"number", "string", "date", "time", "currency", "percentage"}


def _is_blank(value: Any) -> bool:
    if value is None or value is pd.NA:
        return True
    if isinstance(value, float) and math.isnan(value):
        return True
    return False


def _infer_series(values: List[Any]) -> pd.Series:
    """Build a typed Series from raw python values (README §7.3 inference)."""
    present = [v for v in values if not _is_blank(v)]
    if not present:
        return pd.Series([pd.NA] * len(values), dtype="Float64")
    if all(isinstance(v, bool) for v in present):
        return pd.Series([pd.NA if _is_blank(v) else bool(v) for v in values], dtype="boolean")
    if all(isinstance(v, (int, float, np.integer, np.floating)) and not isinstance(v, bool)
           for v in present):
        return pd.Series([pd.NA if _is_blank(v) else float(v) for v in values], dtype="Float64")
    if all(isinstance(v, (_dt.datetime, _dt.date, pd.Timestamp)) and not isinstance(v, _dt.time)
           for v in present):
        return pd.Series([None if _is_blank(v) else pd.Timestamp(v) for v in values],
                         dtype="datetime64[ns]")
    return pd.Series([None if _is_blank(v) else v for v in values], dtype="object")


class BandProxy:
    """Accessor for a label band (``table.top``, ``table.left`` ...).

    Indexing uses the band's own 0-based grid, e.g. ``table.top['A0']`` is the
    first cell of the top band. ``table.top[:] = [...]`` fills the band.
    """

    def __init__(self, table: "Table", region: str) -> None:
        object.__setattr__(self, "_table", table)
        object.__setattr__(self, "_region", region)

    def _shape(self) -> tuple[int, int]:
        return self._table.bands.shape_for(self._region, self._table.body_rows, self._table.body_cols)

    def __getitem__(self, key: Any) -> Any:
        if isinstance(key, slice):
            return self._table._band_grid(self._region)
        ref = _addr.classify(key)
        if isinstance(ref, CellRef):
            return self._table._band_get(self._region, ref.row, ref.col)
        if isinstance(ref, RangeRef):
            return [[self._table._band_get(self._region, r, c)
                     for c in range(ref.col0, ref.col1 + 1)]
                    for r in range(ref.row0, ref.row1 + 1)]
        raise _addr.AddressError(f"Unsupported band reference: {key!r}")

    def __setitem__(self, key: Any, value: Any) -> None:
        if isinstance(key, slice):
            self._table._band_fill(self._region, value)
            return
        ref = _addr.classify(key)
        if isinstance(ref, CellRef):
            self._table._band_set(self._region, ref.row, ref.col, value)
            return
        if isinstance(ref, RangeRef):
            rows = list(value) if isinstance(value, (list, tuple)) else None
            for i, r in enumerate(range(ref.row0, ref.row1 + 1)):
                for j, c in enumerate(range(ref.col0, ref.col1 + 1)):
                    cell = value
                    if rows is not None:
                        row_vals = rows[i] if i < len(rows) else []
                        if isinstance(row_vals, (list, tuple)):
                            cell = row_vals[j] if j < len(row_vals) else None
                        else:
                            cell = row_vals
                    self._table._band_set(self._region, r, c, cell)
            return
        raise _addr.AddressError(f"Unsupported band reference: {key!r}")


class Table:
    def __init__(self, id: str, name: Optional[str] = None, *, rows: int = 10, cols: int = 6,
                 bands: Optional[LabelBands] = None, rect: Optional[Rect] = None) -> None:
        self.id = id
        self.name = name or id
        self.bands = bands or LabelBands()
        self.df = pd.DataFrame(
            {c: pd.Series([pd.NA] * rows, dtype="Float64") for c in range(cols)}
        )
        self.df.columns = pd.RangeIndex(cols)
        # Dense band value grids, region -> list[list[Any]].
        self._labels: Dict[str, List[List[Any]]] = {r: [] for r in _REGIONS}
        # Per body-column display type, col index -> type name.
        self.column_types: Dict[int, str] = {}
        self.rect = rect or Rect()
        self.sync_rect_size()

    # -- geometry -----------------------------------------------------------
    @property
    def body_rows(self) -> int:
        return int(self.df.shape[0])

    @property
    def body_cols(self) -> int:
        return int(self.df.shape[1])

    def sync_rect_size(self) -> None:
        total_cols = self.bands.left + self.body_cols + self.bands.right
        total_rows = self.bands.top + self.body_rows + self.bands.bottom
        self.rect.w = total_cols * CELL_WIDTH
        self.rect.h = total_rows * CELL_HEIGHT

    def set_position(self, x: float, y: float) -> "Table":
        self.rect.x = float(x)
        self.rect.y = float(y)
        return self

    def resize(self, rows: Optional[int] = None, cols: Optional[int] = None) -> "Table":
        self._ensure_size(rows if rows is not None else self.body_rows,
                          cols if cols is not None else self.body_cols,
                          shrink=True)
        return self

    def set_labels(self, top: Optional[int] = None, left: Optional[int] = None,
                   bottom: Optional[int] = None, right: Optional[int] = None) -> "Table":
        if top is not None:
            self.bands.top = int(top)
        if left is not None:
            self.bands.left = int(left)
        if bottom is not None:
            self.bands.bottom = int(bottom)
        if right is not None:
            self.bands.right = int(right)
        self.sync_rect_size()
        return self

    def set_column_type(self, col: int, type: str) -> "Table":
        if type not in COLUMN_TYPES:
            raise ValueError(f"Unknown column type: {type!r}")
        self.column_types[int(col)] = type
        return self

    def minimize(self) -> "Table":
        """Shrink the body to the last non-empty cell (README §5.3)."""
        last_row, last_col = -1, -1
        for r in range(self.body_rows):
            for c in range(self.body_cols):
                if not _is_blank(self.df.iat[r, c]):
                    last_row = max(last_row, r)
                    last_col = max(last_col, c)
        if last_row < 0:
            return self  # empty table: no-op
        self._ensure_size(last_row + 1, last_col + 1, shrink=True)
        return self

    # -- body sizing --------------------------------------------------------
    def _ensure_size(self, rows: int, cols: int, *, shrink: bool = False) -> None:
        rows = max(int(rows), 0)
        cols = max(int(cols), 0)
        cur_rows, cur_cols = self.body_rows, self.body_cols
        target_rows = rows if shrink else max(rows, cur_rows)
        target_cols = cols if shrink else max(cols, cur_cols)
        if target_cols != cur_cols:
            if target_cols > cur_cols:
                for c in range(cur_cols, target_cols):
                    self.df[c] = pd.Series([pd.NA] * self.body_rows, dtype="Float64")
            else:
                self.df = self.df.iloc[:, :target_cols]
                self.column_types = {c: t for c, t in self.column_types.items() if c < target_cols}
            self.df.columns = pd.RangeIndex(target_cols)
        if target_rows != cur_rows:
            if target_rows > cur_rows:
                self.df = self.df.reindex(range(target_rows))
            else:
                self.df = self.df.iloc[:target_rows, :]
            self.df.index = pd.RangeIndex(target_rows)
        self.sync_rect_size()

    # -- body indexing ------------------------------------------------------
    def __getitem__(self, key: str) -> Any:
        named = self._resolve_name(key) if isinstance(key, str) else None
        if named is not None:
            return self.df.iloc[:, named]
        ref = _addr.classify(key)
        if isinstance(ref, CellRef):
            self._check_bounds(ref.row, ref.col)
            return self._native(self.df.iat[ref.row, ref.col])
        if isinstance(ref, ColRef):
            self._check_bounds(0, ref.col)
            return self.df.iloc[:, ref.col]
        if isinstance(ref, RangeRef):
            self._check_bounds(ref.row1, ref.col1)
            return self.df.iloc[ref.row0:ref.row1 + 1, ref.col0:ref.col1 + 1].copy()
        if isinstance(ref, ColRangeRef):
            self._check_bounds(0, ref.col1)
            return self.df.iloc[:, ref.col0:ref.col1 + 1].copy()
        if isinstance(ref, NameRef):
            col = self._resolve_name(ref.name)
            if col is None:
                raise KeyError(f"No column named {ref.name!r} in table {self.id!r}")
            return self.df.iloc[:, col]
        raise _addr.AddressError(f"Unsupported reference: {key!r}")

    def __setitem__(self, key: str, value: Any) -> None:
        named = self._resolve_name(key) if isinstance(key, str) else None
        if named is not None:
            self._assign_columns(named, named, value)
            return
        ref = _addr.classify(key)
        if isinstance(ref, CellRef):
            self._ensure_size(ref.row + 1, ref.col + 1)
            self._set_cell(ref.row, ref.col, value)
            return
        if isinstance(ref, ColRef):
            self._assign_columns(ref.col, ref.col, value)
            return
        if isinstance(ref, RangeRef):
            self._ensure_size(ref.row1 + 1, ref.col1 + 1)
            self._assign_range(ref, value)
            return
        if isinstance(ref, ColRangeRef):
            self._assign_columns(ref.col0, ref.col1, value)
            return
        if isinstance(ref, NameRef):
            col = self._resolve_name(ref.name)
            if col is None:
                col = self._create_named_column(ref.name)
            self._assign_columns(col, col, value)
            return
        raise _addr.AddressError(f"Unsupported reference: {key!r}")

    def _check_bounds(self, row: int, col: int) -> None:
        if row >= self.body_rows or col >= self.body_cols:
            raise IndexError(
                f"Reference out of bounds for table {self.id!r} "
                f"({self.body_rows}x{self.body_cols})"
            )

    def _set_cell(self, row: int, col: int, value: Any) -> None:
        column = self.df.iloc[:, col].tolist()
        column[row] = self._coerce_scalar(value)
        self.df.isetitem(col, _infer_series(column))

    def _assign_columns(self, col0: int, col1: int, value: Any) -> None:
        ncols = col1 - col0 + 1
        self._ensure_size(self.body_rows, col1 + 1)
        columns = self._as_columns(value, ncols)
        for offset, col_values in enumerate(columns):
            col_values = self._fit_rows(col_values)
            self.df.isetitem(col0 + offset, _infer_series(col_values))

    def _assign_range(self, ref: RangeRef, value: Any) -> None:
        nrows = ref.row1 - ref.row0 + 1
        ncols = ref.col1 - ref.col0 + 1
        grid = self._as_grid(value, nrows, ncols)
        for c in range(ncols):
            column = self.df.iloc[:, ref.col0 + c].tolist()
            for r in range(nrows):
                column[ref.row0 + r] = self._coerce_scalar(grid[r][c])
            self.df.isetitem(ref.col0 + c, _infer_series(column))

    # -- value coercion / shaping ------------------------------------------
    def _coerce_scalar(self, value: Any) -> Any:
        value = self._native(value)
        if isinstance(value, str) and value == "":
            return pd.NA
        return value

    @staticmethod
    def _native(value: Any) -> Any:
        if value is pd.NA or value is None:
            return None
        if isinstance(value, np.generic):
            return value.item()
        if isinstance(value, float) and math.isnan(value):
            return None
        return value

    def _fit_rows(self, values: List[Any]) -> List[Any]:
        if len(values) > self.body_rows:
            self._ensure_size(len(values), self.body_cols)
        out = [self._coerce_scalar(v) for v in values]
        if len(out) < self.body_rows:
            out += [pd.NA] * (self.body_rows - len(out))
        return out

    def _as_columns(self, value: Any, ncols: int) -> List[List[Any]]:
        if isinstance(value, pd.DataFrame):
            return [value.iloc[:, c].tolist() for c in range(min(ncols, value.shape[1]))]
        if isinstance(value, pd.Series):
            return [value.tolist()]
        if isinstance(value, np.ndarray):
            value = value.tolist()
        if isinstance(value, (list, tuple)):
            if value and isinstance(value[0], (list, tuple, np.ndarray)):
                # 2D: rows of columns -> transpose
                rows = [list(r) for r in value]
                width = max((len(r) for r in rows), default=0)
                return [[rows[r][c] if c < len(rows[r]) else None for r in range(len(rows))]
                        for c in range(width)]
            return [list(value)]  # single column vector
        # scalar broadcast across rows
        return [[value] * self.body_rows for _ in range(ncols)]

    def _as_grid(self, value: Any, nrows: int, ncols: int) -> List[List[Any]]:
        if isinstance(value, pd.DataFrame):
            value = value.values.tolist()
        elif isinstance(value, pd.Series):
            value = [[v] for v in value.tolist()]
        elif isinstance(value, np.ndarray):
            value = value.tolist()
        if isinstance(value, (list, tuple)):
            rows = list(value)
            if rows and not isinstance(rows[0], (list, tuple, np.ndarray)):
                # flat list: lay out by columns if it's a single row/col, else error
                if nrows == 1:
                    rows = [list(rows)]
                elif ncols == 1:
                    rows = [[v] for v in rows]
                else:
                    raise ValueError("Cannot map a flat list onto a 2D range")
            grid = [[None] * ncols for _ in range(nrows)]
            for r in range(nrows):
                src = list(rows[r]) if r < len(rows) and isinstance(rows[r], (list, tuple, np.ndarray)) else []
                for c in range(ncols):
                    grid[r][c] = src[c] if c < len(src) else None
            return grid
        # scalar broadcast
        return [[value] * ncols for _ in range(nrows)]

    # -- column names / headers --------------------------------------------
    def header_names(self) -> List[Optional[str]]:
        """Column names from the top label row 0, else None per column."""
        if self.bands.top <= 0:
            return [None] * self.body_cols
        row = self._band_grid("top")
        first = row[0] if row else []
        return [(self._native(first[c]) if c < len(first) else None) for c in range(self.body_cols)]

    def _resolve_name(self, name: str) -> Optional[int]:
        for col, header in enumerate(self.header_names()):
            if header is not None and str(header) == name:
                return col
        return None

    def _create_named_column(self, name: str) -> int:
        col = self.body_cols
        self._ensure_size(self.body_rows, col + 1)
        if self.bands.top <= 0:
            self.set_labels(top=1)
        self._band_set("top", 0, col, name)
        return col

    # -- label band storage -------------------------------------------------
    def _band_grid(self, region: str) -> List[List[Any]]:
        rows, cols = self.bands.shape_for(region, self.body_rows, self.body_cols)
        grid = self._labels.get(region) or []
        out = [[None] * cols for _ in range(rows)]
        for r in range(min(rows, len(grid))):
            src = grid[r]
            for c in range(min(cols, len(src))):
                out[r][c] = src[c]
        return out

    def _band_bounds(self, region: str) -> tuple[int, int]:
        return self.bands.shape_for(region, self.body_rows, self.body_cols)

    def _band_get(self, region: str, row: int, col: int) -> Any:
        rows, cols = self._band_bounds(region)
        if row >= rows or col >= cols:
            raise IndexError(f"Band reference out of bounds for {region!r} band")
        grid = self._labels.get(region) or []
        if row < len(grid) and col < len(grid[row]):
            return self._native(grid[row][col])
        return None

    def _band_set(self, region: str, row: int, col: int, value: Any) -> None:
        rows, cols = self._band_bounds(region)
        if row >= rows or col >= cols:
            raise IndexError(
                f"Band cell ({row},{col}) is outside the {region!r} band "
                f"({rows}x{cols}); increase the band count first"
            )
        grid = self._labels.setdefault(region, [])
        while len(grid) <= row:
            grid.append([])
        while len(grid[row]) <= col:
            grid[row].append(None)
        value = self._native(value)
        grid[row][col] = "" if value is None else str(value)

    def _band_fill(self, region: str, values: Any) -> None:
        rows, cols = self._band_bounds(region)
        if isinstance(values, np.ndarray):
            values = values.tolist()
        seq = list(values) if isinstance(values, (list, tuple)) else [values]
        is_2d = bool(seq) and isinstance(seq[0], (list, tuple))
        for r in range(rows):
            for c in range(cols):
                if is_2d:
                    row_vals = seq[r] if r < len(seq) else []
                    cell = row_vals[c] if c < len(row_vals) else None
                else:
                    # single row band: fill row 0 by columns; otherwise broadcast
                    cell = seq[c] if (rows == 1 and c < len(seq)) else (seq[r] if c == 0 and r < len(seq) else None)
                if cell is not None:
                    self._band_set(region, r, c, cell)

    # -- band proxies -------------------------------------------------------
    @property
    def top(self) -> BandProxy:
        return BandProxy(self, "top")

    @property
    def left(self) -> BandProxy:
        return BandProxy(self, "left")

    @property
    def bottom(self) -> BandProxy:
        return BandProxy(self, "bottom")

    @property
    def right(self) -> BandProxy:
        return BandProxy(self, "right")

    # -- graduation ---------------------------------------------------------
    def to_pandas(self, named: bool = False) -> pd.DataFrame:
        """Return a typed copy of the body. With ``named=True`` apply headers."""
        frame = self.df.convert_dtypes().copy()
        frame.columns = pd.RangeIndex(self.body_cols)
        if named:
            names = self.header_names()
            frame.columns = [n if n else _addr.column_label(i) for i, n in enumerate(names)]
        return frame

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"Table(id={self.id!r}, rows={self.body_rows}, cols={self.body_cols})"
