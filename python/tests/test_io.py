import json

from canvassheets import Project, from_dict, to_dict, to_json


def build():
    proj = Project()
    s = proj.add_sheet("Tab1", id="sheet_1")
    t = proj.add_table(s, id="table_1", rows=3, cols=3, labels=dict(top=1))
    t.top[:] = ["A", "B", "Sum"]
    t["A0:A2"] = [1, 2, 3]
    t["B0:B2"] = [10, 20, 30]
    t["C"] = t["A"] + t["B"]
    t.set_column_type(0, "currency")
    return proj


def test_to_dict_shape():
    data = to_dict(build())
    table = data["sheets"][0]["tables"][0]
    assert table["grid"]["rows"] == 3 and table["grid"]["cols"] == 3
    assert table["columns"][0]["name"] == "A"
    assert table["columns"][0]["format"] == "currency"
    assert table["body"][2] == [11, 22, 33]  # column C


def test_json_is_serializable():
    text = to_json(build())
    parsed = json.loads(text)
    assert parsed["version"] == 1


def test_roundtrip_preserves_values():
    data = to_dict(build())
    rebuilt = from_dict(data)
    again = to_dict(rebuilt)
    assert again["sheets"][0]["tables"][0]["body"] == data["sheets"][0]["tables"][0]["body"]
    assert again["sheets"][0]["tables"][0]["labels"]["top"] == [["A", "B", "Sum"]]


def test_empty_cells_are_null():
    proj = Project()
    s = proj.add_sheet()
    t = proj.add_table(s, rows=2, cols=2)
    t["A0"] = 5
    data = to_dict(proj)
    body = data["sheets"][0]["tables"][0]["body"]
    assert body[0][0] == 5
    assert body[1][1] is None
