# Implementation Plan v2: CanvasSheets — pandas-native, script-first

> This is a from-scratch rewrite of the plan. The original `Implememtation_plan.md` and
> `README.md` (spec) are preserved unchanged. This document supersedes the old plan; where it
> conflicts with the spec, this document wins, and the rationale is given inline.

---

## 0. Why rewrite (diagnosis of the current build)

The current implementation works inside the app but fails the two goals you actually care about.
Both failures are structural, not bugs:

1. **The "script" is not runnable Python.** Generated scripts use sugar like
   ```python
   with table_context(table_1):
       f0 = c_sum("B0:E0")
   ```
   These bare assignments (`f0 = ...`) only take effect because the engine `exec`s the file with a
   custom `FormulaLocals` dict (`canvassheets_api/runner.py:12`, `__init__.py:433`) that intercepts
   `__setitem__`/`__missing__`. Run `python script.py` directly and those lines silently do nothing,
   and `proj.apply_formulas()` is never called. The script *only* runs inside the bespoke harness —
   the opposite of your goal.

2. **The data model is not numpy/pandas.** A table's data is a sparse `Dict[str, Any]` keyed by
   strings like `"body[A0]"`, holding JSON-tagged values (`{"type":"number","value":...}`)
   (`__init__.py:1574`+). numpy is barely used; there is no DataFrame anywhere. The spec's promise of
   "columnar typed arrays" (§7.4) never materialized, so there is nothing to "switch to pandas."

3. **A custom spreadsheet-formula language was reimplemented in Python** — tokenizer, parser, AST,
   evaluator (~800 lines, `__init__.py:473`–`1398`) — plus a *second* parallel formula
   representation (`FormulaExpr` operator overloading). Two formula systems, both bespoke, neither
   reusable outside the app.

4. **Charts and summaries are thin pass-throughs.** Summary = a hand-rolled accumulator loop
   (`_apply_summary_table`, `__init__.py:2069`); charts read stale cell-dict values with no live
   recompute and no multi-series. Both are exactly the "not very good" parts you flagged.

5. **The Swift side has a 2227-line `CanvasViewModel` god object** and ~1700 lines of command
   serialization hardwired to the `table_context`/`b0 = ...` DSL. Most of the Python-coupling code
   exists only to normalize/round-trip that fragile DSL.

### Decisions locked in for v2 (your answers)

| Area | Decision |
|---|---|
| Recorded action style | **Explicit method calls** — every line is ordinary Python; runs verbatim with `python script.py`. No exec harness, no magic locals. |
| Formula engine | **Python expressions are the formula.** No custom spreadsheet language. `t['Total'] = t['Q1'] + t['Q2']`. |
| Rewrite scope | **Full from-scratch (Swift + Python).** Salvage only: AppKit grid renderer, range/address parser, document-package layout, `CellValue` codec. |
| Table backing | **A real `pandas.DataFrame` per table body.** Graduating to pandas = take `table.df`. |

### The one idea that makes everything slimmer

Because formulas are ordinary Python statements evaluated top-to-bottom over real DataFrames,
**the script's own execution order is the recalculation engine.** "Rebuild from script" and
"recalculate" become the same operation. That single decision deletes, versus the current build:

- the formula tokenizer/parser/AST/evaluator (~800 lines),
- the `FormulaExpr` operator-overload DSL,
- the `FormulaLocals` exec harness + `table_context`/`label_context` magic,
- the global formula-order counter and dependency bookkeeping,
- and most of the Swift `PythonLogNormalizer` (it exists to round-trip the DSL).

There is no formula engine to build. There is a thin pandas wrapper, a recorder, and a renderer.

---

## 1. Target architecture

```
┌──────────────────────────── Swift (macOS app) ────────────────────────────┐
│  SwiftUI shell: window, sheet tabs, canvas, inspector, code panel          │
│  CanvasStore (small): selection + UI state only                            │
│  Recorder: user action ──► one Python statement ──► append to command log  │
│  DocumentPackage: project.json (layout) + script.py (canonical) + history  │
│  PythonRunner: subprocess bridge ──► runs script.py in bundled CPython     │
│  GridRenderer (salvaged AppKit): draws DataFrame snapshots, virtualized     │
└───────────────────────────────┬────────────────────────────────────────────┘
                                 │ writes script.py, reads back tables.json
┌───────────────────────────────▼──── Python (standalone, pip-installable) ──┐
│  canvassheets/  — a normal package; depends on numpy + pandas              │
│    Project, Sheet, Table (Table wraps a pandas.DataFrame body)            │
│    indexing sugar: t['A0'], t['A'], t['A0:C9'], cross-table t2['B0']      │
│    add_chart(...), add_summary(...) (summary = df.groupby().agg())        │
│    proj.to_json() / from_json()  — the app's read-back contract           │
│    export helpers (standalone numpy / matplotlib)                         │
│  __main__.py — `python -m canvassheets run script.py --emit json`         │
└────────────────────────────────────────────────────────────────────────────┘
```

**Contract between the two halves is small and explicit:**
- Swift writes a `script.py` that imports `canvassheets` and calls explicit methods.
- Swift runs it: `python -m canvassheets run script.py --emit json`.
- The runner executes the user's script unmodified, then prints one JSON blob describing every
  table's computed values (DataFrame → records), label bands, chart specs, and geometry.
- Swift decodes that JSON and renders. No magic, no harness — the same command a user could type.

---

## 2. The Python library `canvassheets` (the heart of the rewrite)

This is built and tested **first and in isolation**, with zero Swift involvement. Success criterion:
a human can `pip install -e .`, write a script by hand, run `python script.py`, and get a correct
result — and the *same* script is what the app generates.

### 2.1 Data model

```python
class Table:
    id: str
    name: str
    df: pandas.DataFrame          # the body — typed columns, this IS the data
    labels: LabelBands            # top/left/bottom/right: small object/str arrays (spec §7.5)
    rect: Rect                    # x, y (w/h derived from grid footprint)
    charts/summary: see §2.4
```

- **Body = a real DataFrame.** Column dtypes are pandas dtypes (`float64`, `Int64` nullable,
  `string`, `datetime64[ns]`, `bool`, plus currency/percent stored as float with a display-format
  tag). This delivers spec §4/§7.4 for real.
- **Label bands map to DataFrame metadata where natural** (this is what makes graduation valuable):
  - top label row 0 → `df.columns` (human names like `Revenue`, `Q1`),
  - left label col 0 → `df.index` (optional),
  - extra label rows/cols → kept in `labels` as plain arrays.
  So `proj.table('t1').df` on graduation is a *named* DataFrame, not a grid of A/B/C.

### 2.2 Addressing & indexing (replaces the bespoke address-space machinery)

Single small parser (salvage the existing Swift `RangeParser` semantics, reimplement ~80 lines in
Python). Spreadsheet letters + 0-based rows, defaulting to the body region:

| Expression | Meaning | pandas underneath |
|---|---|---|
| `t['A']` | column A (a Series) | `t.df.iloc[:, 0]` (or by name `t['Revenue']`) |
| `t['A0']` | one cell (scalar) | `t.df.iat[0, 0]` |
| `t['A0:C9']` | rectangular block | `t.df.iloc[0:10, 0:3]` |
| `t['A0'] = 5` | set a cell | `t.df.iat[0,0] = 5` |
| `t['B0:E19'] = data` | set a block (literal) | block assign |
| `t['F'] = t['B'] + t['C']` | derived column (**this is "a formula"**) | vectorized Series op |
| `t2['B0']` | cross-table cell | resolves on `t2` |
| `t.top['A0']`, `t.left['A0']` | label-band cells (spec §5.4) | `labels` arrays |

There is no `=SUM(...)` string parser. Aggregations are pandas: `t['B'].sum()`,
`t[['B','C']].mean(axis=1)`, `t.df.loc[0:9,'B'].sum()`. A tiny optional helper module
(`canvassheets.fn`) can provide spreadsheet-flavored names (`SUM = lambda s: s.sum()`) for
discoverability, but they return ordinary numbers — no DSL, no magic.

> **Note on the "=SUM" UX (deferred, not in scope):** you chose "Python expressions are the
> formula," so the engine has no spreadsheet language. If you later want a familiar `=SUM(B0:E0)`
> *input affordance* in the formula bar, it can be added as pure front-end sugar in Swift that
> desugars to `t['F'] = t['B0:E0'].sum()` at record time — the recorded script and engine stay
> 100% pandas. This is intentionally left out of v2.

### 2.3 Recompute model & "is this cell a formula?"

The script runs top-to-bottom; pandas evaluates each assignment immediately; later statements
override earlier ones (last-writer-wins per cell). That fully covers spec §5.5.3's "evaluate in
global log order." The app needs to know which cells are *formula-defined* (to show the expression
in the formula bar and to recompute). This is **provenance from the command log, not state in the
cell**:

- The app's command log (see §4) records each statement and its kind:
  `SetLiteral(target, values)` vs `SetExpr(target, expr_text)`.
- To display a selected cell's formula: find the last `SetExpr` whose target range covers that cell;
  show `expr_text`. Otherwise the cell is a literal.
- To recompute: re-run the whole `script.py` (the bundled interpreter run is fast for typical
  sizes; debounced — spec §11.3). No Swift-side dependency graph, ever.

The Table object itself stores only computed values (the DataFrame). Formula *text* lives in the
log/script. This is the clean separation the old build lacked.

### 2.4 Charts and summaries — done right via pandas

**Summary tables = `groupby().agg()`, recorded literally.** This replaces the hand-rolled
accumulator and is both slimmer and strictly more powerful (multi-key, column pivots, any agg):

```python
sales = proj.table('table_1')
summary = proj.add_summary(sheet, source='table_1',
                           group_by=['Region'], values={'Revenue': 'sum', 'Units': 'mean'})
# under the hood, recorded and run as ordinary pandas:
#   _df = sales.df.groupby(['Region']).agg(Revenue=('Revenue','sum'), Units=('Units','mean'))
#   summary.df = _df.reset_index()
```
Column-group pivots (spec §5.6 deferred item) become `pd.pivot_table(...)` later — same path.
Re-running the script recomputes summaries automatically because they are just pandas statements
over the (also recomputed) source.

**Charts** are spec objects bound to table ranges, persisted in `project.json` and recorded as
`proj.add_chart(...)`. Because chart data is read *after* a script run, charts always reflect
computed values (fixing the stale-data weakness). The chart spec is data-binding only; rendering is
Swift's job (§5). Multi-series support comes free: a value range with N columns → N series, series
names from the top label row (spec §5.10.6). For the standalone-Python story, `export` can also emit
a matplotlib snippet so charts survive outside the app.

### 2.5 Serialization contract (`to_json` / `from_json`)

`proj.to_json()` emits, per table: id, name, rect, grid dims, label bands, column dtypes/formats,
and the body as orient-`split` records (compact, dtype-preserving). Charts and summary specs travel
too. This is the only thing Swift parses. `Project.from_json()` round-trips it (used by tests and
for fast-open snapshots, spec §10.4).

### 2.6 Packaging

- A normal `pyproject.toml` package, `pip install -e .`, depends on `numpy`, `pandas`.
- `python -m canvassheets run <script.py> --emit json|numpy|matplotlib`.
- For the app bundle: ship a universal2 CPython + numpy + pandas wheels (spec §13.2). Larger bundle
  than numpy-only, but it's your chosen graduation target and removes all bespoke math.

---

## 3. Build sequence — Python library first (Phases P)

Each phase ships a testable increment. Python tests: `pytest`. The library must be fully usable by
hand before any Swift work begins.

### Phase P1 — Package skeleton + addressing
- `pyproject.toml`, `canvassheets/` package, `Project`/`Sheet`/`Table` shells, `Rect`, `LabelBands`.
- Address/range parser: `A0`, `A`, `A0:C9`, region accessors.
- Tests: `test_addressing.py` (cell/col/range/letters↔index, 0-based rows, band regions).

### Phase P2 — Table as DataFrame + indexing sugar
- `Table.df` backed by pandas; `__getitem__`/`__setitem__` for cell/col/block; cross-table refs.
- `add_table(rows, cols, labels, x, y)`; auto-grow on out-of-bounds writes (spec §5.3).
- Label bands ↔ `df.columns`/`df.index` mapping; dtypes per column.
- Tests: `test_table_indexing.py`, `test_table_grow.py`, `test_label_band_mapping.py`.

### Phase P3 — Formulas-as-Python + recompute-by-rerun
- Confirm derived columns/cells are plain assignments; document last-writer-wins.
- `python -m canvassheets run script.py --emit json`; `to_json`/`from_json` round-trip.
- A **hand-written example script** runs under plain `python script.py` and is checked into tests
  as the canonical "this is what the app generates" fixture.
- Tests: `test_run_script.py` (standalone run), `test_json_roundtrip.py`, `test_recompute_order.py`.

### Phase P4 — Summaries via groupby
- `add_summary(...)` → recorded pandas `groupby().agg().reset_index()`; recompute on rerun.
- Tests: `test_summary.py` (single/multi key, each agg, updates after source change).

### Phase P5 — Charts spec + exports
- `add_chart(...)` spec persistence in `to_json`; multi-series mapping rules.
- `export(--emit numpy)` and `export(--emit matplotlib)` for standalone reuse (spec §5.7, §6.5).
- Tests: `test_chart_spec.py`, `test_export_numpy.py`, `test_export_matplotlib.py`.

**Milestone A (Python done):** a developer can `pip install -e .`, hand-write a script with tables,
derived columns, a summary, and a chart, run it with plain `python script.py`, and get correct
output + JSON. No Swift. This alone satisfies "as close to a pure python script as possible."

---

## 4. The recorder & script format (the Swift↔Python contract)

### 4.1 Script layout (spec §6.4, simplified)
```python
# ===== user code (free editing) =====
import pandas as pd
from canvassheets import Project

# ===== generated (append-only below this marker) =====
proj = Project()
s1 = proj.add_sheet("Tab1", id="sheet_1")
t1 = proj.add_table(s1, id="table_1", x=120, y=120, rows=20, cols=6,
                    labels=dict(top=1, left=1))
t1.top[:] = ["Region","Q1","Q2","Q3","Q4","Total"]
t1["A0:E5"] = [[...]]                       # SetLiteral
t1["F"] = t1["B"] + t1["C"] + t1["D"] + t1["E"]   # SetExpr (a "formula")
proj.run()                                  # materialize summaries/charts; no-op for pure data
```
- One canonical marker line splits user code (above) from generated (below).
- Generated region is data-writes then derived columns then charts/summaries, append-only.
- Single source of truth: an internal **command log** (history.json) is canonical; `script.py` is
  rendered from it *and* is runnable; on "Run", re-parse the generated region back into the log
  (spec §6.4, §20.1). Far simpler now because each command is exactly one statement.

### 4.2 Command set (small, 1:1 with statements)
`AddSheet, AddTable, SetPosition, Resize, Minimize, SetLabelBand, SetLiteral, SetExpr, ClearRange,
SetColumnType, AddSummary, AddChart, SetChartSpec`. Each has `apply(model)` (updates the Swift
display model), `toPython()` (one line), and `invert()` for undo. No `table_context` wrapping, no
log normalizer to merge magic blocks.

### 4.3 Swift serialization
- `PythonLiteralEncoder` (salvage; ~100 lines) for values/dates/escaping.
- Replace the 1459-line `CommandTypes` + `PythonLogNormalizer` with ~300 lines of straight
  statement emission. Most of the deleted code only existed to round-trip the DSL.

---

## 5. Swift app (Phases S) — slim shell over the contract

Rebuild the app around the JSON contract. Salvage list: AppKit grid renderer, `RangeParser`,
`CellValue` codec, document-package layout, the subprocess `PythonRunner` design
(`PythonEngineClient.swift` is reusable as-is in concept — subprocess, timeout, output draining).

### Phase S1 — Document + bridge
- `.nummern` package: `project.json` (layout/specs) + `script.py` + `history.json` (+ snapshots).
- `PythonRunner` (port of `PythonEngineClient`): writes `script.py`, runs the bundled interpreter,
  decodes `to_json`. Bundle universal2 CPython + numpy + pandas.
- Tests: package round-trip; runner decodes a known script to a model.

### Phase S2 — Canvas + tables (geometry only)
- SwiftUI canvas, sheet tabs, draggable/resizable table frames; grid footprint snapping (spec §5.3).
- `CanvasStore` holds **only** selection + UI state (not a god object). Display model is the decoded
  JSON snapshot.
- Tests: move/resize/minimize emit correct commands & rects.

### Phase S3 — Grid rendering (salvaged AppKit) + read-back
- Virtualized AppKit grid draws the DataFrame snapshot (values + dtypes/formats); label bands.
- Tests: visible-range mapping; format display per dtype.

### Phase S4 — Editing → SetLiteral / SetExpr
- Cell/range edit, copy/paste (CSV/TSV), fill. Literal edits → `SetLiteral`; formula-bar Python
  expression → `SetExpr`. Debounced run → re-render (spec §11.3).
- Formula bar shows provenance expression for derived cells (§2.3); click-to-insert references.
- Tests: literal vs expr recording; paste relative-ref adjustment; provenance lookup.

### Phase S5 — Code panel + run
- Editable script with the marker; Run All / Run Selection / Reset Runtime; stderr→line mapping;
  re-parse generated region into the command log after a run.
- Tests: marker preservation; selection-run injects imports/`proj`; traceback line parse.

### Phase S6 — Summaries & charts UI
- Selection-aware Create Summary (range/table scope) → `AddSummary`; pivot builder (group keys +
  value aggs).
- Chart create from selection (multi-series rules, spec §5.10.6); inspector for type/title/legend/
  ranges; SwiftUI Charts rendering of computed values.
- Tests: summary source-range scoping; chart range derivation; live update after source edit.

### Phase S7 — Undo/redo + CSV + polish
- `UndoManager` over command inverses (incl. `ClearRange`); CSV import (dtype inference) / export.
- Interaction model pass (spec §5.10): keyboard commit/move rules, multi-range selection.
- Snapshot fast-open (spec §10.4) validated against script hash.
- Accessibility/perf pass.

---

## 6. Milestones

- **Milestone A — Standalone Python library** (after P5): hand-writable, `pip`-installable,
  `python script.py` runs; pandas-native; summaries & charts via pandas. *Delivers the core thesis
  independently of the app.*
- **Milestone B — MVP app** (after S5): create sheets/tables, edit, derive columns, run, rebuild
  from script, code panel. Every UI action produces a line you could have typed.
- **Milestone C — v1** (after S7): summaries, charts, undo/redo, CSV, snapshots, interaction model.

## 7. What we are deliberately NOT building (kept out for slimness)
- No custom spreadsheet-formula language / parser / evaluator (pandas is the engine).
- No `FormulaExpr` DSL, no `FormulaLocals` exec harness, no `table_context` magic.
- No Swift-side dependency graph or incremental recalc (rerun-the-script covers it; optimize later
  only if profiling demands).
- No `=SUM()` input affordance in v2 (can be added later as pure front-end sugar — §2.2 note).
- No XPC service in MVP (plain subprocess like today is sufficient and simpler; revisit for v1+).

## 8. Open considerations to confirm during P1
1. **Cross-table reference syntax** in recorded scripts: `t2['B0']` (object form, chosen) vs a
   string form. Object form is pure Python and chosen; confirm it reads well in generated logs.
2. **Per-cell heterogeneous formulas** are awkward in a column model (pandas is column-oriented).
   v2 favors column/range expressions; per-cell formulas use `.iat`/`.loc` assignments. Confirm this
   matches how you expect to work, or we add a thin per-cell expr table.
3. **Nullable dtypes**: use pandas nullable `Int64`/`boolean`/`string` so empty cells survive
   round-trips without float-coercion surprises. Default new numeric columns to `Float64`.
4. **Bundle size**: CPython + numpy + pandas universal2 is ~tens of MB. Acceptable given the
   "graduate to pandas" goal; flagged so it's a conscious choice.
