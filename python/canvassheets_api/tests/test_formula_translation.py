from __future__ import annotations

import math

import pytest

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
        "body[B0]": 1,
        "body[B1]": 2,
        "body[B2]": 3,
    })
    table.set_formula("body[C0]", "=np.sum(B0:B2)")
    project.apply_formulas()
    assert table.cell_values["body[C0]"] == 6


def test_range_formula_relative_refs():
    project = Project()
    table = _make_table(project, "table_1", rows=3, cols=3)
    table.set_cells({
        "body[A0]": 1,
        "body[A1]": 2,
        "body[A2]": 3,
        "body[B0]": 10,
        "body[B1]": 20,
        "body[B2]": 30,
    })
    table.set_formula("body[C0:C2]", "=A0+B0")
    project.apply_formulas()
    assert table.cell_values["body[C0]"] == 11
    assert table.cell_values["body[C1]"] == 22
    assert table.cell_values["body[C2]"] == 33


def test_cross_table_reference():
    project = Project()
    table_1 = _make_table(project, "table_1", rows=2, cols=2)
    table_1.set_cells({"body[A0]": 5})

    table_2 = project.add_table(
        "sheet_1",
        table_id="table_2",
        name="table_2",
        rect=Rect(0, 0, 100, 100),
        rows=2,
        cols=2,
        labels=None,
    )
    table_2.set_formula("body[B0]", "=table_1.A0*2")
    project.apply_formulas()
    assert table_2.cell_values["body[B0]"] == 10


def test_absolute_reference():
    project = Project()
    table = _make_table(project, "table_1", rows=3, cols=3)
    table.set_cells({
        "body[A0]": 2,
        "body[B0]": 10,
        "body[B1]": 20,
        "body[B2]": 30,
    })
    table.set_formula("body[C0:C2]", "=$A$0+B0")
    project.apply_formulas()
    assert table.cell_values["body[C0]"] == 12
    assert table.cell_values["body[C1]"] == 22
    assert table.cell_values["body[C2]"] == 32


def test_column_reference_function():
    project = Project()
    table = _make_table(project, "table_1", rows=3, cols=3)
    table.set_cells({
        "body[A0]": 1,
        "body[A1]": 2,
        "body[A2]": 3,
    })
    table.set_formula("body[B0]", "=SUM(col(A))")
    project.apply_formulas()
    assert table.cell_values["body[B0]"] == 6


def test_table_prefixed_column_reference():
    project = Project()
    table_1 = _make_table(project, "table_1", rows=3, cols=2)
    table_1.set_cells({
        "body[A0]": 4,
        "body[A1]": 5,
        "body[A2]": 6,
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
    table_2.set_formula("body[B0]", "=SUM(table_1.A)")
    project.apply_formulas()
    assert table_2.cell_values["body[B0]"] == 15


def test_table_prefixed_row_reference():
    project = Project()
    table_1 = _make_table(project, "table_1", rows=3, cols=3)
    table_1.set_cells({
        "body[A1]": 1,
        "body[B1]": 2,
        "body[C1]": 3,
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
    table_2.set_formula("body[A0]", "=SUM(table_1.1)")
    project.apply_formulas()
    assert table_2.cell_values["body[A0]"] == 6


def test_math_formula_functions():
    project = Project()
    table = _make_table(project, "table_1", rows=2, cols=2)
    table.set_cells({"body[A0]": -5, "body[A1]": 1.234})
    table.set_formula("body[B0]", "=ABS(A0)")
    table.set_formula("body[B1]", "=ROUND(A1, 1)")
    project.apply_formulas()
    assert table.cell_values["body[B0]"] == 5
    assert table.cell_values["body[B1]"] == pytest.approx(1.2)


def test_pmt_formula_function():
    project = Project()
    table = _make_table(project, "table_1", rows=1, cols=2)
    table.set_formula("body[B0]", "=PMT(0.1, 2, 100)")
    project.apply_formulas()
    expected = -(0.1 * (100 * (1 + 0.1) ** 2)) / ((1 + 0.1 * 0) * ((1 + 0.1) ** 2 - 1))
    assert table.cell_values["body[B0]"] == pytest.approx(expected)
