"""Canonical recorded script.

This is exactly the shape the app generates. It must run under plain
`python canonical.py` with no special harness — that is the headline proof that
recorded scripts are real, standalone Python.
"""

import pandas as pd  # noqa: F401  (apps may import pandas in the user region)

from canvassheets import Project

proj = Project()
sheet = proj.add_sheet("Tab1", id="sheet_1")

# A revenue table with a top header band and a left label band.
t1 = proj.add_table(sheet, id="table_1", x=120, y=120, rows=4, cols=6,
                    labels=dict(top=1, left=1))
t1.top[:] = ["Region", "Q1", "Q2", "Q3", "Q4", "Total"]
t1.left[:] = ["North", "South", "East", "West"]

# Body data (literal block).
t1["B0:E3"] = [
    [10, 12, 14, 16],
    [20, 22, 24, 26],
    [30, 32, 34, 36],
    [40, 42, 44, 46],
]

# A "formula" is just a pandas expression. Total = sum of the quarter columns.
t1["F"] = t1["B"] + t1["C"] + t1["D"] + t1["E"]

# A second table referencing the first across tables.
t2 = proj.add_table(sheet, id="table_2", x=700, y=120, rows=1, cols=2, labels=dict(top=1))
t2.top[:] = ["GrandTotal", "Average"]
t2["A0"] = t1["F"].sum()
t2["B0"] = t1["F"].mean()

proj.run()

if __name__ == "__main__":
    # Standalone run prints a quick summary (proves it executes on its own).
    print("table_1 totals:", [float(v) for v in t1["F"]])
    print("grand total:", float(t2["A0"]), "average:", float(t2["B0"]))
