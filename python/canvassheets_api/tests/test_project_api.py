from __future__ import annotations

import json

import numpy as np

from canvassheets_api import (
    Project,
    Rect,
    _DEFAULT_CELL_HEIGHT,
    _DEFAULT_CELL_WIDTH,
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
