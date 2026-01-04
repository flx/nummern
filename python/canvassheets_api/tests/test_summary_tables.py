from canvassheets_api import Project, address


def _make_project():
    proj = Project()
    proj.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = proj.add_table("sheet_1", table_id="table_1", name="table_1", rows=3, cols=2)
    table.set_cells(
        {
            address("body", 0, 0): "Group 1",
            address("body", 0, 1): 1,
            address("body", 1, 0): "Group 1",
            address("body", 1, 1): 2,
            address("body", 2, 0): "Group 2",
            address("body", 2, 1): 5,
        }
    )
    return proj


def test_summary_table_sum():
    proj = _make_project()
    proj.add_summary_table(
        "sheet_1",
        table_id="summary_1",
        name="summary_1",
        source_table_id="table_1",
        group_by=["A"],
        values=[{"col": "B", "agg": "sum"}],
    )
    proj.apply_formulas()
    summary = proj.table("summary_1")
    assert summary.grid_spec.bodyRows == 2
    assert summary.grid_spec.bodyCols == 2
    assert summary.cell_values[address("body", 0, 0)] == "Group 1"
    assert summary.cell_values[address("body", 0, 1)] == 3
    assert summary.cell_values[address("body", 1, 0)] == "Group 2"
    assert summary.cell_values[address("body", 1, 1)] == 5


def test_summary_updates_on_change():
    proj = _make_project()
    proj.add_summary_table(
        "sheet_1",
        table_id="summary_1",
        name="summary_1",
        source_table_id="table_1",
        group_by=["A"],
        values=[{"col": "B", "agg": "sum"}],
    )
    proj.apply_formulas()
    proj.table("table_1").set_cells({address("body", 1, 1): 10})
    proj.apply_formulas()
    summary = proj.table("summary_1")
    assert summary.cell_values[address("body", 0, 1)] == 11
