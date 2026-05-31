# canvassheets

A pandas-backed, script-first canvas spreadsheet engine. Every recorded action is
plain, runnable Python — there is no custom exec harness and no spreadsheet
formula language.

```python
from canvassheets import Project

proj = Project()
sheet = proj.add_sheet("Tab1")
t = proj.add_table(sheet, rows=4, cols=6, labels=dict(top=1, left=1))
t.top[:] = ["Region", "Q1", "Q2", "Q3", "Q4", "Total"]
t["B0:E3"] = [[10, 12, 14, 16], [20, 22, 24, 26], [30, 32, 34, 36], [40, 42, 44, 46]]

# A "formula" is just a pandas expression over the table:
t["F"] = t["B"] + t["C"] + t["D"] + t["E"]

proj.run()
print(t.to_pandas(named=True))   # graduate to pandas: a real, named DataFrame
```

## Core ideas

- **The table body is a real `pandas.DataFrame`** (`table.df`). Graduate with
  `table.to_pandas(named=True)` for typed, header-named columns.
- **Formulas are Python.** `t["Total"] = t["Q1"] + t["Q2"]`. No parser, no DSL.
- **Re-running the script *is* recalculation.** The runner executes the file in a
  normal namespace and serializes the result.

## Indexing

| Expression | Meaning |
|---|---|
| `t["A0"]` | one cell (scalar) |
| `t["A"]` | a column (Series) |
| `t["A0:C9"]` | a rectangular block (DataFrame) |
| `t["Revenue"]` | a column by its header name |
| `t.top["A0"]`, `t.left[:] = [...]` | label-band cells |

A1-style refs are uppercase; a token with a lowercase letter (e.g. `Revenue`) is a
column name. Table indexing resolves header names before positional refs.

## CLI

```sh
python -m canvassheets run script.py --emit json        # the app's contract
python -m canvassheets run script.py --emit numpy        # standalone snapshot
python -m canvassheets run script.py --emit matplotlib   # snapshot + plotting
```

## Develop

```sh
pip install -e .
pytest
```

Requires Python ≥ 3.10, numpy ≥ 2.0, pandas ≥ 2.2.
