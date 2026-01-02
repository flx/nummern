from __future__ import annotations

from canvassheets_api import FormulaLocals, Project, Rect, formula, table_context, label_context, c_sum


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


def test_cross_table_formula_order():
    globals_dict = FormulaLocals({"__builtins__": __builtins__})
    globals_dict["proj"] = Project()
    globals_dict["Rect"] = Rect
    globals_dict["table_context"] = table_context
    globals_dict["c_sum"] = c_sum
    globals_dict["formula"] = formula

    exec(
        "proj.add_sheet('Sheet 1', sheet_id='sheet_1')\n"
        "t1 = proj.add_table('sheet_1', table_id='table_1', name='table_1', rect=Rect(0,0,10,10), rows=4, cols=3)\n"
        "with table_context(t1):\n"
        "    a1 = 1\n"
        "    a2 = 2\n"
        "    a3 = 3\n"
        "    b3 = c_sum('a1:a3')\n"
        "t2 = proj.add_table('sheet_1', table_id='table_2', name='table_2', rect=Rect(0,0,10,10), rows=4, cols=3)\n"
        "with table_context(t2):\n"
        "    b3 = 1\n"
        "    a1 = 2\n"
        "    c3 = formula('B3+A1+table_1::B3')\n"
        "with table_context(t1):\n"
        "    b4 = formula('table_2::C3+table_2::B3+A1')\n",
        globals_dict,
        globals_dict,
    )

    proj = globals_dict["proj"]
    proj.apply_formulas()
    table_1 = proj.table("table_1")
    table_2 = proj.table("table_2")
    assert table_2.cell_values["body[C3]"] == 9
    assert table_1.cell_values["body[B4]"] == 11


def test_cross_table_attribute_sugar():
    globals_dict = FormulaLocals({"__builtins__": __builtins__})
    globals_dict["proj"] = Project()
    globals_dict["Rect"] = Rect
    globals_dict["table_context"] = table_context

    exec(
        "proj.add_sheet('Sheet 1', sheet_id='sheet_1')\n"
        "t1 = proj.add_table('sheet_1', table_id='table_1', name='table_1', rect=Rect(0,0,10,10), rows=2, cols=2)\n"
        "t2 = proj.add_table('sheet_1', table_id='table_2', name='table_2', rect=Rect(0,0,10,10), rows=2, cols=2)\n"
        "table_2 = proj.table('table_2')\n"
        "with table_context(t2):\n"
        "    b1 = 7\n"
        "with table_context(t1):\n"
        "    a1 = table_2.b1\n",
        globals_dict,
        globals_dict,
    )

    proj = globals_dict["proj"]
    proj.apply_formulas()
    table_1 = proj.table("table_1")
    assert table_1.cell_values["body[A1]"] == 7
