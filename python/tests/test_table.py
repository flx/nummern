import numpy as np
import pandas as pd
import pytest

from canvassheets import LabelBands, Table


def make_table(rows=4, cols=3, **bands):
    return Table("table_1", rows=rows, cols=cols, bands=LabelBands(**bands) if bands else None)


def test_new_table_is_numeric_and_empty():
    t = make_table()
    assert t.body_rows == 4 and t.body_cols == 3
    assert t["A0"] is None


def test_cell_get_set():
    t = make_table()
    t["A0"] = 5
    t["B1"] = 2.5
    assert t["A0"] == 5
    assert t["B1"] == 2.5


def test_column_and_range_access():
    t = make_table()
    t["A0:A3"] = [1, 2, 3, 4]
    col = t["A"]
    assert isinstance(col, pd.Series)
    assert list(col) == [1, 2, 3, 4]
    block = t["A0:A1"]
    assert isinstance(block, pd.DataFrame)
    assert block.shape == (2, 1)


def test_derived_column_is_just_pandas():
    t = make_table()
    t["A0:A3"] = [1, 2, 3, 4]
    t["B0:B3"] = [10, 20, 30, 40]
    t["C"] = t["A"] + t["B"]
    assert list(t["C"]) == [11, 22, 33, 44]


def test_mean_axis_on_numeric_columns():
    t = make_table()
    t["A0:A3"] = [1, 2, 3, 4]
    t["B0:B3"] = [3, 4, 5, 6]
    t["C"] = t["A0:B3"].mean(axis=1)
    assert list(t["C"]) == [2, 3, 4, 5]


def test_write_beyond_bounds_autogrows():
    t = make_table(rows=2, cols=2)
    t["D5"] = 9
    assert t.body_rows == 6 and t.body_cols == 4
    assert t["D5"] == 9


def test_string_promotes_column_to_object():
    t = make_table()
    t["A0"] = "hello"
    assert t["A0"] == "hello"
    assert t.to_pandas().dtypes.iloc[0] == object or str(t.to_pandas().dtypes.iloc[0]) == "string"


def test_read_out_of_bounds_raises():
    t = make_table(rows=2, cols=2)
    with pytest.raises(IndexError):
        _ = t["Z9"]


def test_set_range_2d_block():
    t = make_table()
    t["A0:B1"] = [[1, 2], [3, 4]]
    assert t["A0"] == 1 and t["B0"] == 2 and t["A1"] == 3 and t["B1"] == 4


def test_label_bands_and_headers():
    t = make_table(cols=3, top=1, left=1)
    t.top[:] = ["Region", "Q1", "Q2"]
    assert t.top["A0"] == "Region"
    assert t.header_names() == ["Region", "Q1", "Q2"]
    # named access resolves through the header row
    t["Q1"] = [1, 2, 3, 4]
    assert list(t["Q1"]) == [1, 2, 3, 4]


def test_named_column_creation_adds_header():
    t = make_table(cols=2, top=1)
    t.top[:] = ["A", "B"]
    t["Total"] = [1, 1, 1, 1]
    assert t.body_cols == 3
    assert t.header_names()[2] == "Total"
    assert list(t["Total"]) == [1, 1, 1, 1]


def test_resize_and_minimize():
    t = make_table(rows=10, cols=10)
    t["B1"] = 7
    t.minimize()
    assert t.body_rows == 2 and t.body_cols == 2
    t.resize(rows=5, cols=5)
    assert t.body_rows == 5 and t.body_cols == 5


def test_to_pandas_named():
    t = make_table(cols=2, top=1)
    t.top[:] = ["x", "y"]
    t["A0:A1"] = [1, 2]
    frame = t.to_pandas(named=True)
    assert list(frame.columns) == ["x", "y"]


def test_numpy_value_assignment():
    t = make_table()
    t["A0:A3"] = np.array([1.0, 2.0, 3.0, 4.0])
    assert list(t["A"]) == [1, 2, 3, 4]
