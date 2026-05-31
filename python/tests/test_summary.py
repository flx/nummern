import pytest

from canvassheets import Project


def build_source():
    proj = Project()
    s = proj.add_sheet()
    t = proj.add_table(s, id="sales", rows=5, cols=3, labels=dict(top=1))
    t.top[:] = ["Region", "Revenue", "Units"]
    t["A0:A4"] = ["North", "South", "North", "South", "North"]
    t["B0:B4"] = [10, 20, 30, 40, 50]
    t["C0:C4"] = [1, 2, 3, 4, 5]
    return proj, s, t


def test_summary_sum_by_group():
    proj, s, t = build_source()
    summary = proj.add_summary(s, "sales", group_by="Region",
                               values={"Revenue": "sum"})
    proj.run()
    # North: 10+30+50 = 90 ; South: 20+40 = 60
    regions = list(summary["A"])
    revenues = list(summary["B"])
    by = dict(zip(regions, revenues))
    assert by == {"North": 90, "South": 60}
    assert summary.header_names()[:2] == ["Region", "Revenue"]


def test_summary_multiple_aggs():
    proj, s, t = build_source()
    summary = proj.add_summary(s, "sales", group_by="Region",
                               values=[("Revenue", "sum"), ("Units", "max")])
    proj.run()
    assert summary.body_cols == 3


def test_summary_updates_on_source_change():
    proj, s, t = build_source()
    summary = proj.add_summary(s, "sales", group_by="Region", values={"Revenue": "sum"})
    proj.run()
    first = dict(zip(list(summary["A"]), list(summary["B"])))
    assert first["North"] == 90
    t["B0"] = 1000  # change North's first revenue (was 10)
    proj.run()
    second = dict(zip(list(summary["A"]), list(summary["B"])))
    assert second["North"] == 1080


def test_summary_no_group_global_aggregate():
    proj, s, t = build_source()
    summary = proj.add_summary(s, "sales", group_by=None, values={"Revenue": "sum"})
    proj.run()
    assert summary["A0"] == 150


def test_summary_by_letter_reference():
    proj, s, t = build_source()
    summary = proj.add_summary(s, "sales", group_by="A", values={"B": "sum"})
    proj.run()
    assert summary.body_rows == 2


def test_unknown_aggregation_raises():
    proj, s, t = build_source()
    with pytest.raises(ValueError):
        proj.add_summary(s, "sales", group_by="Region", values={"Revenue": "median"})
