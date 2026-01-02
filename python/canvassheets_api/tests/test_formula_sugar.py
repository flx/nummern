from __future__ import annotations

from canvassheets_api import FormulaLocals, Project, Rect, table_context, label_context, c_sum


def test_formula_assignment_sugar():
    globals_dict = FormulaLocals({"__builtins__": __builtins__})
    globals_dict["proj"] = Project()
    globals_dict["Rect"] = Rect
    globals_dict["table_context"] = table_context
    globals_dict["c_sum"] = c_sum

    exec(
        "proj.add_sheet('Sheet 1', sheet_id='sheet_1')\n"
        "t = proj.add_table('sheet_1', table_id='table_1', name='table_1', rect=Rect(0,0,10,10), rows=3, cols=3)\n"
        "t.set_cells({'body[A1]': 1, 'body[A2]': 2})\n"
        "with table_context(t):\n"
        "    b1 = a1 + a2\n",
        globals_dict,
        globals_dict,
    )

    proj = globals_dict["proj"]
    proj.apply_formulas()
    table = proj.table("table_1")
    assert table.cell_values["body[B1]"] == 3


def test_range_sum_sugar():
    globals_dict = FormulaLocals({"__builtins__": __builtins__})
    globals_dict["proj"] = Project()
    globals_dict["Rect"] = Rect
    globals_dict["table_context"] = table_context
    globals_dict["c_sum"] = c_sum

    exec(
        "proj.add_sheet('Sheet 1', sheet_id='sheet_1')\n"
        "t = proj.add_table('sheet_1', table_id='table_1', name='table_1', rect=Rect(0,0,10,10), rows=3, cols=3)\n"
        "t.set_cells({'body[A1]': 1, 'body[A2]': 2, 'body[B1]': 3})\n"
        "with table_context(t):\n"
        "    c1 = c_sum('A1:B2')\n",
        globals_dict,
        globals_dict,
    )

    proj = globals_dict["proj"]
    proj.apply_formulas()
    table = proj.table("table_1")
    assert table.cell_values["body[C1]"] == 6


def test_label_assignment_sugar():
    globals_dict = FormulaLocals({"__builtins__": __builtins__})
    globals_dict["proj"] = Project()
    globals_dict["Rect"] = Rect
    globals_dict["label_context"] = label_context

    exec(
        "proj.add_sheet('Sheet 1', sheet_id='sheet_1')\n"
        "t = proj.add_table('sheet_1', table_id='table_1', name='table_1', rect=Rect(0,0,10,10), rows=3, cols=3)\n"
        "with label_context(t, 'top_labels'):\n"
        "    a1 = 'Header'\n",
        globals_dict,
        globals_dict,
    )

    table = globals_dict["proj"].table("table_1")
    assert table.cell_values["top_labels[A1]"] == "Header"
