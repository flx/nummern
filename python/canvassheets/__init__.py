"""canvassheets — a pandas-backed, script-first canvas spreadsheet engine.

Every recorded action is plain, runnable Python. A table body is a real
``pandas.DataFrame``; a "formula" is an ordinary Python expression over tables.
"""

from __future__ import annotations

from .address import column_index, column_label, parse_cell, parse_range
from .charts import ChartSpec
from .export import export_matplotlib_script, export_numpy_script
from .geometry import LabelBands, Rect
from .io import from_dict, to_dict, to_json
from .project import Project, Sheet
from .runner import run_script
from .summary import SummarySpec, SummaryTable
from .table import Table

__version__ = "0.1.0"

__all__ = [
    "Project",
    "Sheet",
    "Table",
    "Rect",
    "LabelBands",
    "ChartSpec",
    "SummarySpec",
    "SummaryTable",
    "to_dict",
    "to_json",
    "from_dict",
    "run_script",
    "export_numpy_script",
    "export_matplotlib_script",
    "column_index",
    "column_label",
    "parse_cell",
    "parse_range",
    "__version__",
]
