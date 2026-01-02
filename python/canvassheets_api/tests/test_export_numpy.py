from __future__ import annotations

import numpy as np

from canvassheets_api import Project, Rect, export_numpy_script


def test_export_numpy_script_builds_tables():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = project.add_table(
        "sheet_1",
        table_id="table_1",
        name="table_1",
        rect=Rect(0, 0, 10, 10),
        rows=2,
        cols=2,
        labels=dict(top=1, left=1, bottom=0, right=0),
    )
    table.set_cells({
        "body[A1]": 1,
        "body[B1]": 2,
        "body[B2]": 4,
        "top_labels[A1]": "Header",
        "left_labels[A1]": "Row1",
    })
    table.set_formula("body[A2]", "=SUM(A1:B1)")

    script = export_numpy_script(project, include_labels=True, include_formulas=True)
    globals_dict: dict[str, object] = {"__builtins__": __builtins__}
    exec(script, globals_dict, globals_dict)

    tables = globals_dict["tables"]
    body = tables["table_1"]["body"]
    expected = np.array([[1.0, 2.0], [3.0, 4.0]], dtype=float)
    assert np.allclose(body, expected, equal_nan=True)
    assert tables["table_1"]["labels"]["top"][0][0] == "Header"
    assert tables["table_1"]["labels"]["left"][0][0] == "Row1"
    assert "body[A2]" in tables["table_1"]["formulas"]
