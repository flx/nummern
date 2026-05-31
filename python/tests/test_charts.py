import pytest

from canvassheets import ChartSpec, Project, to_dict


def build():
    proj = Project()
    s = proj.add_sheet()
    t = proj.add_table(s, id="t1", rows=4, cols=3, labels=dict(top=1))
    t.top[:] = ["Month", "A", "B"]
    t["A0:A3"] = ["Jan", "Feb", "Mar", "Apr"]
    t["B0:B3"] = [1, 2, 3, 4]
    t["C0:C3"] = [4, 3, 2, 1]
    return proj, s, t


def test_add_chart_persists_in_json():
    proj, s, t = build()
    chart = proj.add_chart(s, "line", "t1", value_range="B0:C3",
                           label_range="A0:A3", title="Trend")
    assert chart.id == "chart_1"
    data = to_dict(proj)
    charts = data["sheets"][0]["charts"]
    assert len(charts) == 1
    assert charts[0]["chart_type"] == "line"
    assert charts[0]["value_range"] == "B0:C3"
    assert charts[0]["title"] == "Trend"


def test_chart_type_validation():
    proj, s, t = build()
    with pytest.raises(ValueError):
        proj.add_chart(s, "scatter", "t1", value_range="B0:C3")


def test_chart_spec_roundtrip():
    spec = ChartSpec(id="c1", name="c1", chart_type="bar", table_id="t1",
                     value_range="B0:B3", title="x")
    again = ChartSpec.from_dict(spec.to_dict())
    assert again.chart_type == "bar"
    assert again.value_range == "B0:B3"


def test_chart_set_spec_edits_in_place():
    proj, s, t = build()
    chart = proj.add_chart(s, "line", "t1", value_range="B0:C3")
    chart.set_spec(chart_type="bar", title="Updated", show_legend=False)
    data = to_dict(proj)["sheets"][0]["charts"][0]
    assert data["chart_type"] == "bar"
    assert data["title"] == "Updated"
    assert data["show_legend"] is False
    # value_range preserved when not passed
    assert data["value_range"] == "B0:C3"

