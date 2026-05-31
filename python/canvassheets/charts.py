"""Chart specifications — data binding only; rendering is the app's job.

A chart binds to a table's value range (and optional label range). Because the
app reads chart data *after* a script run, charts always reflect computed values.
Multi-series: a value range with N columns yields N series.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Dict, Optional

from .geometry import Rect

__all__ = ["ChartSpec", "CHART_TYPES"]

CHART_TYPES = {"line", "bar", "pie"}


@dataclass
class ChartSpec:
    id: str
    name: str
    chart_type: str
    table_id: str
    value_range: str
    label_range: Optional[str] = None
    title: str = ""
    x_axis_title: str = ""
    y_axis_title: str = ""
    show_legend: bool = True
    rect: Rect = field(default_factory=Rect)

    def __post_init__(self) -> None:
        if self.chart_type not in CHART_TYPES:
            raise ValueError(f"Unknown chart type: {self.chart_type!r}")

    def to_dict(self) -> Dict[str, Any]:
        data = {k: v for k, v in asdict(self).items() if k != "rect"}
        data["rect"] = self.rect.to_dict()
        return data

    @staticmethod
    def from_dict(data: Dict[str, Any]) -> "ChartSpec":
        return ChartSpec(
            id=data["id"],
            name=data.get("name", data["id"]),
            chart_type=data["chart_type"],
            table_id=data["table_id"],
            value_range=data["value_range"],
            label_range=data.get("label_range"),
            title=data.get("title", ""),
            x_axis_title=data.get("x_axis_title", ""),
            y_axis_title=data.get("y_axis_title", ""),
            show_legend=bool(data.get("show_legend", True)),
            rect=Rect.from_dict(data.get("rect")),
        )
