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

    _UNSET = object()

    def set_position(self, x: float, y: float) -> "ChartSpec":
        self.rect.x = float(x)
        self.rect.y = float(y)
        return self

    def set_spec(self, chart_type: Optional[str] = None, value_range: Optional[str] = None,
                 label_range: Any = _UNSET, title: Optional[str] = None,
                 x_axis_title: Optional[str] = None, y_axis_title: Optional[str] = None,
                 show_legend: Optional[bool] = None) -> "ChartSpec":
        """Edit a chart in place (recorded as ``chart_id.set_spec(...)``)."""
        if chart_type is not None:
            if chart_type not in CHART_TYPES:
                raise ValueError(f"Unknown chart type: {chart_type!r}")
            self.chart_type = chart_type
        if value_range is not None:
            self.value_range = value_range
        if label_range is not ChartSpec._UNSET:
            self.label_range = label_range
        if title is not None:
            self.title = title
        if x_axis_title is not None:
            self.x_axis_title = x_axis_title
        if y_axis_title is not None:
            self.y_axis_title = y_axis_title
        if show_legend is not None:
            self.show_legend = bool(show_legend)
        return self

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
