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
        "t.set_cells({'body[A0]': 1, 'body[A1]': 2})\n"
        "with table_context(t):\n"
        "    b0 = a0 + a1\n",
        globals_dict,
        globals_dict,
    )

    proj = globals_dict["proj"]
    proj.apply_formulas()
    table = proj.table("table_1")
    assert table.cell_values["body[B0]"] == 3


def test_range_sum_sugar():
    globals_dict = FormulaLocals({"__builtins__": __builtins__})
    globals_dict["proj"] = Project()
    globals_dict["Rect"] = Rect
    globals_dict["table_context"] = table_context
    globals_dict["c_sum"] = c_sum

    exec(
        "proj.add_sheet('Sheet 1', sheet_id='sheet_1')\n"
        "t = proj.add_table('sheet_1', table_id='table_1', name='table_1', rect=Rect(0,0,10,10), rows=3, cols=3)\n"
        "t.set_cells({'body[A0]': 1, 'body[A1]': 2, 'body[B0]': 3})\n"
        "with table_context(t):\n"
        "    c0 = c_sum('A0:B1')\n",
        globals_dict,
        globals_dict,
    )

    proj = globals_dict["proj"]
    proj.apply_formulas()
    table = proj.table("table_1")
    assert table.cell_values["body[C0]"] == 6


def test_table_indexing_sugar():
    globals_dict = FormulaLocals({"__builtins__": __builtins__})
    globals_dict["proj"] = Project()
    globals_dict["Rect"] = Rect
    globals_dict["table_context"] = table_context

    exec(
        "proj.add_sheet('Sheet 1', sheet_id='sheet_1')\n"
        "t = proj.add_table('sheet_1', table_id='table_1', name='table_1', rect=Rect(0,0,10,10), rows=2, cols=2)\n"
        "with table_context(t):\n"
        "    t[0, 0] = 1\n"
        "    t[0, 1] = t[0, 0] + 2\n",
        globals_dict,
        globals_dict,
    )

    proj = globals_dict["proj"]
    proj.apply_formulas()
    table = proj.table("table_1")
    assert table.cell_values["body[B0]"] == 3


def test_label_assignment_sugar():
    globals_dict = FormulaLocals({"__builtins__": __builtins__})
    globals_dict["proj"] = Project()
    globals_dict["Rect"] = Rect
    globals_dict["label_context"] = label_context

    exec(
        "proj.add_sheet('Sheet 1', sheet_id='sheet_1')\n"
        "t = proj.add_table('sheet_1', table_id='table_1', name='table_1', rect=Rect(0,0,10,10), rows=3, cols=3)\n"
        "with label_context(t, 'top_labels'):\n"
        "    a0 = 'Header'\n",
        globals_dict,
        globals_dict,
    )

    table = globals_dict["proj"].table("table_1")
    assert table.cell_values["top_labels[A0]"] == "Header"


def test_label_formula_sugar():
    globals_dict = FormulaLocals({"__builtins__": __builtins__})
    globals_dict["proj"] = Project()
    globals_dict["Rect"] = Rect
    globals_dict["table_context"] = table_context
    globals_dict["c_sum"] = c_sum

    exec(
        "proj.add_sheet('Sheet 1', sheet_id='sheet_1')\n"
        "t = proj.add_table('sheet_1', table_id='table_1', name='table_1', rect=Rect(0,0,10,10), "
        "rows=3, cols=3, labels={'top': 1, 'left': 0, 'bottom': 0, 'right': 0})\n"
        "t.set_cells({'body[A0]': 1, 'body[A1]': 2})\n"
        "with table_context(t):\n"
        "    top_labels.a0 = c_sum('A0:A1')\n",
        globals_dict,
        globals_dict,
    )

    proj = globals_dict["proj"]
    proj.apply_formulas()
    table = proj.table("table_1")
    assert table.cell_values["top_labels[A0]"] == 3


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
        "    a0 = 1\n"
        "    a1 = 2\n"
        "    a2 = 3\n"
        "    b2 = c_sum('a0:a2')\n"
        "t2 = proj.add_table('sheet_1', table_id='table_2', name='table_2', rect=Rect(0,0,10,10), rows=4, cols=3)\n"
        "with table_context(t2):\n"
        "    b2 = 1\n"
        "    a0 = 2\n"
        "    c2 = formula('B2+A0+table_1.B2')\n"
        "with table_context(t1):\n"
        "    b3 = formula('table_2.C2+table_2.B2+A0')\n",
        globals_dict,
        globals_dict,
    )

    proj = globals_dict["proj"]
    proj.apply_formulas()
    table_1 = proj.table("table_1")
    table_2 = proj.table("table_2")
    assert table_2.cell_values["body[C2]"] == 9
    assert table_1.cell_values["body[B3]"] == 11


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
        "    b0 = 7\n"
        "with table_context(t1):\n"
        "    a0 = table_2.b0\n",
        globals_dict,
        globals_dict,
    )

    proj = globals_dict["proj"]
    proj.apply_formulas()
    table_1 = proj.table("table_1")
    assert table_1.cell_values["body[A0]"] == 7
