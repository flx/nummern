from __future__ import annotations

from canvassheets_api import Project, Rect


def _make_table(project: Project, table_id: str, rows: int = 5, cols: int = 5):
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    return project.add_table(
        "sheet_1",
        table_id=table_id,
        name=table_id,
        rect=Rect(0, 0, 100, 100),
        rows=rows,
        cols=cols,
        labels=None,
    )


def test_sum_range_formula():
    project = Project()
    table = _make_table(project, "table_1", rows=3, cols=3)
    table.set_cells({
        "body[B1]": 1,
        "body[B2]": 2,
        "body[B3]": 3,
    })
    table.set_formula("body[C1]", "=np.sum(B1:B3)")
    project.apply_formulas()
    assert table.cell_values["body[C1]"] == 6


def test_range_formula_relative_refs():
    project = Project()
    table = _make_table(project, "table_1", rows=3, cols=3)
    table.set_cells({
        "body[A1]": 1,
        "body[A2]": 2,
        "body[A3]": 3,
        "body[B1]": 10,
        "body[B2]": 20,
        "body[B3]": 30,
    })
    table.set_formula("body[C1:C3]", "=A1+B1")
    project.apply_formulas()
    assert table.cell_values["body[C1]"] == 11
    assert table.cell_values["body[C2]"] == 22
    assert table.cell_values["body[C3]"] == 33


def test_cross_table_reference():
    project = Project()
    table_1 = _make_table(project, "table_1", rows=2, cols=2)
    table_1.set_cells({"body[A1]": 5})

    table_2 = project.add_table(
        "sheet_1",
        table_id="table_2",
        name="table_2",
        rect=Rect(0, 0, 100, 100),
        rows=2,
        cols=2,
        labels=None,
    )
    table_2.set_formula("body[B1]", "=table_1::A1*2")
    project.apply_formulas()
    assert table_2.cell_values["body[B1]"] == 10


def test_absolute_reference():
    project = Project()
    table = _make_table(project, "table_1", rows=3, cols=3)
    table.set_cells({
        "body[A1]": 2,
        "body[B1]": 10,
        "body[B2]": 20,
        "body[B3]": 30,
    })
    table.set_formula("body[C1:C3]", "=$A$1+B1")
    project.apply_formulas()
    assert table.cell_values["body[C1]"] == 12
    assert table.cell_values["body[C2]"] == 22
    assert table.cell_values["body[C3]"] == 32


def test_column_reference_function():
    project = Project()
    table = _make_table(project, "table_1", rows=3, cols=3)
    table.set_cells({
        "body[A1]": 1,
        "body[A2]": 2,
        "body[A3]": 3,
    })
    table.set_formula("body[B1]", "=SUM(col(A))")
    project.apply_formulas()
    assert table.cell_values["body[B1]"] == 6


def test_table_prefixed_column_reference():
    project = Project()
    table_1 = _make_table(project, "table_1", rows=3, cols=2)
    table_1.set_cells({
        "body[A1]": 4,
        "body[A2]": 5,
        "body[A3]": 6,
    })
    table_2 = project.add_table(
        "sheet_1",
        table_id="table_2",
        name="table_2",
        rect=Rect(0, 0, 100, 100),
        rows=2,
        cols=2,
        labels=None,
    )
    table_2.set_formula("body[B1]", "=SUM(table_1::A)")
    project.apply_formulas()
    assert table_2.cell_values["body[B1]"] == 15


def test_table_prefixed_row_reference():
    project = Project()
    table_1 = _make_table(project, "table_1", rows=3, cols=3)
    table_1.set_cells({
        "body[A2]": 1,
        "body[B2]": 2,
        "body[C2]": 3,
    })
    table_2 = project.add_table(
        "sheet_1",
        table_id="table_2",
        name="table_2",
        rect=Rect(0, 0, 100, 100),
        rows=2,
        cols=2,
        labels=None,
    )
    table_2.set_formula("body[A1]", "=SUM(table_1::2)")
    project.apply_formulas()
    assert table_2.cell_values["body[A1]"] == 6
