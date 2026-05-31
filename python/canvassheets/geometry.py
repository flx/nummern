"""Geometry and grid-structure value types (pure, no pandas)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Optional

__all__ = ["Rect", "LabelBands", "CELL_WIDTH", "CELL_HEIGHT"]

# Canvas cell footprint, in points. Table width/height derive from the grid.
CELL_WIDTH = 80.0
CELL_HEIGHT = 24.0


@dataclass
class Rect:
    x: float = 0.0
    y: float = 0.0
    w: float = 0.0
    h: float = 0.0

    def to_dict(self) -> Dict[str, float]:
        return {"x": self.x, "y": self.y, "w": self.w, "h": self.h}

    @staticmethod
    def from_dict(data: Optional[Dict[str, Any]]) -> "Rect":
        data = data or {}
        return Rect(
            float(data.get("x", 0.0)),
            float(data.get("y", 0.0)),
            float(data.get("w", 0.0)),
            float(data.get("h", 0.0)),
        )


@dataclass
class LabelBands:
    """Counts of label rows/cols around the body (README §5.3)."""

    top: int = 0
    left: int = 0
    bottom: int = 0
    right: int = 0

    def to_dict(self) -> Dict[str, int]:
        return {"top": self.top, "left": self.left, "bottom": self.bottom, "right": self.right}

    @staticmethod
    def from_dict(data: Optional[Dict[str, Any]]) -> "LabelBands":
        data = data or {}
        return LabelBands(
            int(data.get("top", 0)),
            int(data.get("left", 0)),
            int(data.get("bottom", 0)),
            int(data.get("right", 0)),
        )

    def shape_for(self, region: str, body_rows: int, body_cols: int) -> tuple[int, int]:
        """(rows, cols) of a band's own grid, given the body size."""
        if region == "top":
            return (self.top, body_cols)
        if region == "bottom":
            return (self.bottom, body_cols)
        if region == "left":
            return (body_rows, self.left)
        if region == "right":
            return (body_rows, self.right)
        raise ValueError(f"Unknown label region: {region!r}")
