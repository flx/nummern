import pytest

from canvassheets_api import Project


def test_summary_table_respects_source_range():
    proj = Project()
    proj.add_sheet("Sheet 1", sheet_id="sheet_1")
    table = proj.add_table("sheet_1",
                           table_id="table_1",
                           name="table_1",
                           x=0,
                           y=0,
                           rows=4,
                           cols=2,
                           labels=dict(top=0, left=0, bottom=0, right=0))
    table.set_cells(
        {
            "body[A0]": 1,
            "body[A1]": 2,
            "body[A2]": 3,
            "body[A3]": 4,
            "body[B0]": 10,
            "body[B1]": 20,
            "body[B2]": 30,
            "body[B3]": 40,
        }
    )

    summary = proj.add_summary_table("sheet_1",
                                     table_id="summary_1",
                                     name="summary_1",
                                     source_table_id="table_1",
                                     source_range="body[A1:B2]",
                                     group_by=["A"],
                                     values=[dict(col="B", agg="sum")])
    proj.apply_formulas()

    assert summary.cell_values["body[A0]"] == pytest.approx(2)
    assert summary.cell_values["body[B0]"] == pytest.approx(20)
    assert summary.cell_values["body[A1]"] == pytest.approx(3)
    assert summary.cell_values["body[B1]"] == pytest.approx(30)
