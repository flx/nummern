"""Summary (pivot-like) tables — a thin, recorded wrapper over ``groupby().agg()``.

A summary table recomputes itself from its source on ``project.run()``. The whole
operation is ordinary pandas, so "graduating to pandas" needs no translation.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple, Union

import pandas as pd

from . import address as _addr
from .geometry import LabelBands, Rect
from .table import Table

__all__ = ["SummarySpec", "SummaryTable", "AGGREGATIONS"]

# spreadsheet name -> pandas agg
AGGREGATIONS = {"sum": "sum", "avg": "mean", "mean": "mean", "min": "min", "max": "max", "count": "count"}


@dataclass
class SummarySpec:
    source_table_id: str
    group_by: List[str]
    values: List[Tuple[str, str]]  # (column ref, aggregation)
    source_range: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "source_table_id": self.source_table_id,
            "group_by": list(self.group_by),
            "values": [{"col": col, "agg": agg} for col, agg in self.values],
            "source_range": self.source_range,
        }


class SummaryTable(Table):
    """A read-only table whose body is derived from a source via groupby."""

    def __init__(self, id: str, name: Optional[str], spec: SummarySpec, rect: Rect) -> None:
        super().__init__(id, name, rows=1, cols=max(1, len(spec.group_by) + len(spec.values)),
                         bands=LabelBands(top=1), rect=rect)
        self.summary_spec = spec

    def recompute(self, project: "Any") -> None:
        spec = self.summary_spec
        source = project.table(spec.source_table_id)
        frame = source.to_pandas(named=True)
        frame = _restrict_range(frame, spec.source_range)

        group_labels = [_resolve_label(source, frame, ref) for ref in spec.group_by]
        agg_specs: Dict[str, Tuple[str, str]] = {}
        for ref, agg in spec.values:
            label = _resolve_label(source, frame, ref)
            pandas_agg = AGGREGATIONS.get(str(agg).lower())
            if pandas_agg is None:
                raise ValueError(f"Unsupported aggregation: {agg!r}")
            out_name = _unique(label if pandas_agg != "count" else f"{label} (count)", agg_specs)
            agg_specs[out_name] = (label, pandas_agg)

        if group_labels:
            grouped = frame.groupby(group_labels, dropna=True, sort=False)
            result = grouped.agg(**{name: (col, fn) for name, (col, fn) in agg_specs.items()})
            result = result.reset_index()
        else:
            row = {name: getattr(frame[col], fn)() for name, (col, fn) in agg_specs.items()}
            result = pd.DataFrame([row])

        self._write_result(result)

    def _write_result(self, result: pd.DataFrame) -> None:
        rows, cols = max(1, result.shape[0]), max(1, result.shape[1])
        self._ensure_size(rows, cols, shrink=True)
        self.set_labels(top=1)
        for c, name in enumerate(result.columns):
            self._band_set("top", 0, c, str(name))
        for c in range(result.shape[1]):
            values = [None if pd.isna(v) else _native(v) for v in result.iloc[:, c].tolist()]
            self[f"{_addr.column_label(c)}0:{_addr.column_label(c)}{rows - 1}"] = values


def _native(value: Any) -> Any:
    import numpy as np

    if isinstance(value, np.generic):
        return value.item()
    return value


def _unique(name: str, existing: Dict[str, Any]) -> str:
    if name not in existing:
        return name
    i = 2
    while f"{name} {i}" in existing:
        i += 1
    return f"{name} {i}"


def _resolve_label(source: Table, frame: pd.DataFrame, ref: Union[str, int]) -> Any:
    """Resolve a column ref (letter or header name) to the frame's column label."""
    if isinstance(ref, int):
        return frame.columns[ref]
    classified = _addr.classify(ref)
    if isinstance(classified, _addr.ColRef):
        return frame.columns[classified.col]
    if isinstance(classified, _addr.NameRef):
        if ref in frame.columns:
            return ref
        pos = source._resolve_name(ref)
        if pos is not None:
            return frame.columns[pos]
    raise KeyError(f"Cannot resolve summary column {ref!r}")


def _restrict_range(frame: pd.DataFrame, source_range: Optional[str]) -> pd.DataFrame:
    if not source_range:
        return frame
    text = source_range
    if "[" in text and text.endswith("]"):  # tolerate body[A0:C9]
        text = text[text.index("[") + 1:-1]
    r0, c0, r1, c1 = _addr.parse_range(text)
    return frame.iloc[r0:r1 + 1, c0:c1 + 1]


def add_summary(project: "Any", sheet: "Any", source: Union[str, Table], group_by: Any,
                values: Any, *, source_range: Optional[str] = None, id: Optional[str] = None,
                name: Optional[str] = None, x: Optional[float] = None,
                y: Optional[float] = None) -> SummaryTable:
    owner = project.sheet(sheet) if isinstance(sheet, str) else sheet
    source_id = source if isinstance(source, str) else source.id
    project.table(source_id)  # validate it exists
    spec = SummarySpec(
        source_table_id=source_id,
        group_by=_as_ref_list(group_by),
        values=_as_value_list(values),
        source_range=source_range,
    )
    table_id = id or project._next_id("table")
    if id is not None:
        project._observe_id("table", id)
    rect = project._default_rect(x, y)
    table = SummaryTable(table_id, name, spec, rect)
    owner.tables.append(table)
    table.recompute(project)
    return table


def _as_ref_list(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return [str(v) for v in value]
    return [str(value)]


def _as_value_list(value: Any) -> List[Tuple[str, str]]:
    if isinstance(value, dict):
        return [(str(col), str(agg)) for col, agg in value.items()]
    if isinstance(value, (list, tuple)):
        out: List[Tuple[str, str]] = []
        for item in value:
            if isinstance(item, dict):
                out.append((str(item["col"]), str(item["agg"])))
            elif isinstance(item, (list, tuple)) and len(item) == 2:
                out.append((str(item[0]), str(item[1])))
            else:
                raise ValueError("Each summary value must be (col, agg) or {'col','agg'}")
        return out
    raise ValueError("Summary values must be a dict or a list of (col, agg)")
