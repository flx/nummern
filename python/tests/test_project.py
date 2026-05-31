import pytest

from canvassheets import Project


def test_add_sheet_and_table_auto_ids():
    proj = Project()
    s = proj.add_sheet("Tab1")
    assert s.id == "sheet_1"
    t = proj.add_table(s, rows=3, cols=3)
    assert t.id == "table_1"
    assert proj.table("table_1") is t
    assert proj.sheet("sheet_1") is s


def test_explicit_ids_keep_counter_ahead():
    proj = Project()
    s = proj.add_sheet(id="sheet_1")
    proj.add_table(s, id="table_5", rows=1, cols=1)
    t = proj.add_table(s, rows=1, cols=1)
    assert t.id == "table_6"


def test_duplicate_id_raises():
    proj = Project()
    s = proj.add_sheet(id="sheet_1")
    proj.add_table(s, id="t", rows=1, cols=1)
    with pytest.raises(ValueError):
        proj.add_table(s, id="t", rows=1, cols=1)


def test_cross_table_reference():
    proj = Project()
    s = proj.add_sheet()
    a = proj.add_table(s, rows=2, cols=1)
    b = proj.add_table(s, rows=1, cols=1)
    a["A0:A1"] = [3, 4]
    b["A0"] = a["A"].sum()
    assert b["A0"] == 7


def test_default_rect_offsets_each_table():
    proj = Project()
    s = proj.add_sheet()
    t1 = proj.add_table(s, rows=1, cols=1)
    t2 = proj.add_table(s, rows=1, cols=1)
    assert (t2.rect.x, t2.rect.y) != (t1.rect.x, t1.rect.y)


def test_rect_size_tracks_grid():
    proj = Project()
    s = proj.add_sheet()
    t = proj.add_table(s, rows=4, cols=2, labels=dict(top=1, left=1))
    # (left + cols + right) * 80 ; (top + rows + bottom) * 24
    assert t.rect.w == (1 + 2) * 80.0
    assert t.rect.h == (1 + 4) * 24.0
