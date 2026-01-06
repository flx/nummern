from __future__ import annotations

import math

import pytest

from canvassheets_api import (
    FormulaLocals,
    Project,
    Rect,
    formula,
    table_context,
    label_context,
    c_range,
    c_sum,
    c_avg,
    c_min,
    c_max,
    c_count,
    c_counta,
    c_if,
    c_and,
    c_or,
    c_not,
    c_pmt,
    c_abs,
    c_round,
    c_floor,
    c_ceil,
    c_sqrt,
    c_pow,
    c_log,
    c_log10,
    c_exp,
    c_sin,
    c_cos,
    c_tan,
)


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


def test_formula_helper_aggregates():
    globals_dict = FormulaLocals({"__builtins__": __builtins__})
    globals_dict["proj"] = Project()
    globals_dict["Rect"] = Rect
    globals_dict["table_context"] = table_context
    globals_dict["c_range"] = c_range
    globals_dict["c_sum"] = c_sum
    globals_dict["c_avg"] = c_avg
    globals_dict["c_min"] = c_min
    globals_dict["c_max"] = c_max
    globals_dict["c_count"] = c_count
    globals_dict["c_counta"] = c_counta

    exec(
        "proj.add_sheet('Sheet 1', sheet_id='sheet_1')\n"
        "t = proj.add_table('sheet_1', table_id='table_1', name='table_1', rect=Rect(0,0,10,10), rows=4, cols=4)\n"
        "t.set_cells({'body[A0]': 1, 'body[A1]': 2, 'body[A2]': 3, 'body[B0]': 'text', "
        "'body[B1]': '', 'body[B2]': None})\n"
        "with table_context(t):\n"
        "    c0 = c_avg('A0:A2')\n"
        "    c1 = c_min('A0:A2')\n"
        "    c2 = c_max('A0:A2')\n"
        "    c3 = c_sum(c_range('A0:A2'))\n"
        "    c4 = c_count('A0:B2')\n"
        "    c5 = c_counta('A0:B2')\n",
        globals_dict,
        globals_dict,
    )

    proj = globals_dict["proj"]
    proj.apply_formulas()
    table = proj.table("table_1")
    assert table.cell_values["body[C0]"] == 2.0
    assert table.cell_values["body[C1]"] == 1
    assert table.cell_values["body[C2]"] == 3
    assert table.cell_values["body[C3]"] == 6
    assert table.cell_values["body[C4]"] == 3
    assert table.cell_values["body[C5]"] == 4


def test_formula_helper_logical():
    globals_dict = FormulaLocals({"__builtins__": __builtins__})
    globals_dict["proj"] = Project()
    globals_dict["Rect"] = Rect
    globals_dict["table_context"] = table_context
    globals_dict["c_if"] = c_if
    globals_dict["c_and"] = c_and
    globals_dict["c_or"] = c_or
    globals_dict["c_not"] = c_not

    exec(
        "proj.add_sheet('Sheet 1', sheet_id='sheet_1')\n"
        "t = proj.add_table('sheet_1', table_id='table_1', name='table_1', rect=Rect(0,0,10,10), rows=3, cols=3)\n"
        "t.set_cells({'body[A0]': 1, 'body[A1]': 0})\n"
        "with table_context(t):\n"
        "    b0 = c_and(a0, a1)\n"
        "    b1 = c_or(a0, a1)\n"
        "    b2 = c_not(a1)\n"
        "    b3 = c_if(c_and(a0, a1), 10, 20)\n",
        globals_dict,
        globals_dict,
    )

    proj = globals_dict["proj"]
    proj.apply_formulas()
    table = proj.table("table_1")
    assert table.cell_values["body[B0]"] is False
    assert table.cell_values["body[B1]"] is True
    assert table.cell_values["body[B2]"] is True
    assert table.cell_values["body[B3]"] == 20


def test_formula_helper_math():
    globals_dict = FormulaLocals({"__builtins__": __builtins__})
    globals_dict["proj"] = Project()
    globals_dict["Rect"] = Rect
    globals_dict["table_context"] = table_context
    globals_dict["c_pmt"] = c_pmt
    globals_dict["c_abs"] = c_abs
    globals_dict["c_round"] = c_round
    globals_dict["c_floor"] = c_floor
    globals_dict["c_ceil"] = c_ceil
    globals_dict["c_sqrt"] = c_sqrt
    globals_dict["c_pow"] = c_pow
    globals_dict["c_log"] = c_log
    globals_dict["c_log10"] = c_log10
    globals_dict["c_exp"] = c_exp
    globals_dict["c_sin"] = c_sin
    globals_dict["c_cos"] = c_cos
    globals_dict["c_tan"] = c_tan

    exec(
        "proj.add_sheet('Sheet 1', sheet_id='sheet_1')\n"
        "t = proj.add_table('sheet_1', table_id='table_1', name='table_1', rect=Rect(0,0,10,10), "
        "rows=13, cols=2)\n"
        "with table_context(t):\n"
        "    b0 = c_abs(-5)\n"
        "    b1 = c_round(1.234, 1)\n"
        "    b2 = c_floor(1.9)\n"
        "    b3 = c_ceil(1.1)\n"
        "    b4 = c_sqrt(9)\n"
        "    b5 = c_pow(2, 3)\n"
        "    b6 = c_log(100, 10)\n"
        "    b7 = c_log10(100)\n"
        "    b8 = c_exp(1)\n"
        "    b9 = c_sin(0)\n"
        "    b10 = c_cos(0)\n"
        "    b11 = c_tan(0)\n"
        "    b12 = c_pmt(0.1, 2, 100)\n",
        globals_dict,
        globals_dict,
    )

    proj = globals_dict["proj"]
    proj.apply_formulas()
    table = proj.table("table_1")
    assert table.cell_values["body[B0]"] == 5
    assert table.cell_values["body[B1]"] == pytest.approx(1.2)
    assert table.cell_values["body[B2]"] == 1
    assert table.cell_values["body[B3]"] == 2
    assert table.cell_values["body[B4]"] == 3
    assert table.cell_values["body[B5]"] == 8
    assert table.cell_values["body[B6]"] == pytest.approx(2.0)
    assert table.cell_values["body[B7]"] == pytest.approx(2.0)
    assert table.cell_values["body[B8]"] == pytest.approx(math.e)
    assert table.cell_values["body[B9]"] == pytest.approx(0.0)
    assert table.cell_values["body[B10]"] == pytest.approx(1.0)
    assert table.cell_values["body[B11]"] == pytest.approx(0.0)
    assert table.cell_values["body[B12]"] == pytest.approx(-57.619047619, rel=1e-6)


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
