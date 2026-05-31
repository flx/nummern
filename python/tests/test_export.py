from canvassheets import Project, export_matplotlib_script, export_numpy_script


def build():
    proj = Project()
    s = proj.add_sheet()
    t = proj.add_table(s, id="t1", rows=3, cols=2, labels=dict(top=1))
    t.top[:] = ["A", "B"]
    t["A0:A2"] = [1, 2, 3]
    t["B0:B2"] = [4, 5, 6]
    return proj, s, t


def test_numpy_export_executes_standalone():
    proj, s, t = build()
    script = export_numpy_script(proj)
    namespace = {}
    exec(compile(script, "<numpy-export>", "exec"), namespace)  # noqa: S102
    tables = namespace["tables"]
    assert tables["t1"]["body"].tolist() == [[1.0, 4.0], [2.0, 5.0], [3.0, 6.0]]
    assert tables["t1"]["labels"]["top"] == [["A", "B"]]


def test_matplotlib_export_includes_chart_code():
    proj, s, t = build()
    proj.add_chart(s, "bar", "t1", value_range="A0:B2", title="demo")
    script = export_matplotlib_script(proj)
    assert "import matplotlib.pyplot as plt" in script
    assert "ax.bar" in script
    assert "plt.show()" in script
