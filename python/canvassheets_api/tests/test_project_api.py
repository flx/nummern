from __future__ import annotations

import json

import numpy as np
import pytest

from canvassheets_api import (
    Project,
    Rect,
    _DEFAULT_CELL_HEIGHT,
    _DEFAULT_CELL_WIDTH,
    date_value,
    time_value,
)


def test_project_rename_sheet():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    project.rename_sheet("sheet_1", name="Renamed")
    assert project.to_dict()["sheets"][0]["name"] == "Renamed"


def test_json_export_handles_numpy_bool():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = project.add_table(
        "sheet_1",
        table_id="table_1",
        name="table_1",
        rect=Rect(0, 0, 10, 10),
        rows=1,
        cols=1,
    )
    table.set_cells({"body[A0]": np.bool_(True)})
    json.dumps(project.to_dict())


def test_rect_updates_after_resize_and_labels():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = project.add_table(
        "sheet_1",
        table_id="table_1",
        name="table_1",
        rows=2,
        cols=3,
        labels=dict(top=0, left=0, bottom=0, right=0),
        x=0,
        y=0,
    )

    assert table.rect.width == 3 * _DEFAULT_CELL_WIDTH
    assert table.rect.height == 2 * _DEFAULT_CELL_HEIGHT

    table.set_labels(top=1, left=1, bottom=1, right=1)
    assert table.rect.width == 5 * _DEFAULT_CELL_WIDTH
    assert table.rect.height == 4 * _DEFAULT_CELL_HEIGHT

    table.insert_rows(at=0, count=2)
    assert table.rect.height == 6 * _DEFAULT_CELL_HEIGHT

    table.insert_cols(at=0, count=1)
    assert table.rect.width == 6 * _DEFAULT_CELL_WIDTH


def test_set_position_updates_origin():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = project.add_table(
        "sheet_1",
        table_id="table_1",
        name="table_1",
        rows=1,
        cols=1,
        labels=dict(top=0, left=0, bottom=0, right=0),
        x=10,
        y=20,
    )

    table.set_position(42, 84)

    assert table.rect.x == 42
    assert table.rect.y == 84


def test_setitem_expands_table():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = project.add_table(
        "sheet_1",
        table_id="table_1",
        name="table_1",
        rows=2,
        cols=2,
        labels=dict(top=0, left=0, bottom=0, right=0),
        x=0,
        y=0,
    )

    table[3, 4] = 1

    assert table.grid_spec.bodyRows == 4
    assert table.grid_spec.bodyCols == 5
    assert table.rect.width == 5 * _DEFAULT_CELL_WIDTH
    assert table.rect.height == 4 * _DEFAULT_CELL_HEIGHT


def test_minimize_shrinks_table():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = project.add_table(
        "sheet_1",
        table_id="table_1",
        name="table_1",
        rows=6,
        cols=6,
        labels=dict(top=0, left=0, bottom=0, right=0),
        x=0,
        y=0,
    )

    table[2, 3] = 1
    table.minimize()

    assert table.grid_spec.bodyRows == 3
    assert table.grid_spec.bodyCols == 4


def test_date_time_cells_roundtrip():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = project.add_table(
        "sheet_1",
        table_id="table_1",
        name="table_1",
        rows=1,
        cols=2,
        labels=dict(top=0, left=0, bottom=0, right=0),
        x=0,
        y=0,
    )

    table.set_cells({
        "body[A0]": date_value("2024-01-15"),
        "body[B0]": time_value("13:45:30"),
    })

    data = project.to_dict()
    cell_values = data["sheets"][0]["tables"][0]["cellValues"]
    assert cell_values["body[A0]"] == {"type": "date", "value": "2024-01-15"}
    assert cell_values["body[B0]"] == {"type": "time", "value": "13:45:30"}


def test_set_column_type_updates_table():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = project.add_table(
        "sheet_1",
        table_id="table_1",
        name="table_1",
        rows=2,
        cols=2,
        labels=dict(top=0, left=0, bottom=0, right=0),
        x=0,
        y=0,
    )

    table.set_column_type(1, "currency")
    table.set_column_type(3, "date")

    assert table.grid_spec.bodyCols == 4
    data = project.to_dict()
    body_types = data["sheets"][0]["tables"][0]["bodyColumnTypes"]
    assert body_types[1] == "currency"
    assert body_types[3] == "date"


def test_table_attribute_assignment_sets_cell():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = project.add_table(
        "sheet_1",
        table_id="table_1",
        name="table_1",
        rows=1,
        cols=1,
        labels=dict(top=0, left=0, bottom=0, right=0),
        x=0,
        y=0,
    )

    table.c2 = 5

    assert table.grid_spec.bodyRows == 3
    assert table.grid_spec.bodyCols == 3
    assert table.cell_values["body[C2]"] == 5


def test_chart_roundtrip_and_updates():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    project.add_table(
        "sheet_1",
        table_id="table_1",
        name="table_1",
        rows=3,
        cols=1,
        labels=dict(top=0, left=0, bottom=0, right=0),
        x=0,
        y=0,
    )

    chart = project.add_chart(
        "sheet_1",
        chart_id="chart_1",
        name="chart_1",
        chart_type="line",
        table_id="table_1",
        value_range="body[A0:A2]",
        label_range=None,
        x=10,
        y=20,
        width=300,
        height=200,
        title="",
        x_axis_title="",
        y_axis_title="",
        show_legend=True,
    )
    chart.set_position(40, 60)
    chart.set_spec(chart_type="bar", label_range=None, title="Sales", show_legend=False)

    data = project.to_dict()
    chart_payload = data["sheets"][0]["charts"][0]
    assert chart_payload["rect"]["x"] == 40
    assert chart_payload["rect"]["y"] == 60
    assert chart_payload["chartType"] == "bar"
    assert chart_payload["labelRange"] is None
    assert chart_payload["title"] == "Sales"
    assert chart_payload["showLegend"] is False


def test_set_range_clears_overlapping_formula():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = project.add_table(
        "sheet_1",
        table_id="table_1",
        name="table_1",
        rows=1,
        cols=1,
        labels=dict(top=0, left=0, bottom=0, right=0),
        x=0,
        y=0,
    )

    table.set_formula("body[A0]", "=1+1")
    table.set_range("body[A0:A0]", [[5]])

    assert "body[A0]" not in table.formulas
    assert table.cell_values["body[A0]"] == 5


def test_set_cells_clears_overlapping_formula_range():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = project.add_table(
        "sheet_1",
        table_id="table_1",
        name="table_1",
        rows=1,
        cols=2,
        labels=dict(top=0, left=0, bottom=0, right=0),
        x=0,
        y=0,
    )

    table.set_formula("body[A0:B0]", "=A0+1")
    table.set_cells({"body[B0]": 9})

    assert "body[A0:B0]" not in table.formulas
    assert table.cell_values["body[B0]"] == 9


def test_set_range_normalizes_ragged_rows():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = project.add_table(
        "sheet_1",
        table_id="table_1",
        name="table_1",
        rows=2,
        cols=2,
        labels=dict(top=0, left=0, bottom=0, right=0),
        x=0,
        y=0,
    )

    table.set_range("body[A0:B1]", [[1], [2, 3]])

    assert table.range_values["body[A0:B1]"]["values"] == [[1, None], [2, 3]]
    assert table.cell_values["body[A0]"] == 1
    assert table.cell_values["body[B0]"] is None
    assert table.cell_values["body[A1]"] == 2
    assert table.cell_values["body[B1]"] == 3


def test_duplicate_ids_rejected():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    with pytest.raises(ValueError):
        project.add_sheet("Sheet 2", sheet_id="sheet_1")

    project.add_table("sheet_1", table_id="table_1", name="table_1", rows=1, cols=1, x=0, y=0)
    with pytest.raises(ValueError):
        project.add_table("sheet_1", table_id="table_1", name="other", rows=1, cols=1, x=10, y=10)

    project.add_chart("sheet_1",
                      chart_id="chart_1",
                      name="chart_1",
                      chart_type="line",
                      table_id="table_1",
                      value_range="body[A0:A0]",
                      x=0,
                      y=0)
    with pytest.raises(ValueError):
        project.add_chart("sheet_1",
                          chart_id="chart_1",
                          name="chart_2",
                          chart_type="bar",
                          table_id="table_1",
                          value_range="body[A0:A0]",
                          x=10,
                          y=10)


def test_unsupported_formula_mode_raises():
    project = Project()
    project.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = project.add_table("sheet_1", table_id="table_1", name="table_1", rows=1, cols=1, x=0, y=0)

    with pytest.raises(ValueError):
        table.set_formula("body[A0]", "x+1", mode="python")
