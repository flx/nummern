# Specification: macOS Canvas Spreadsheet with Python Event Log (Swift/SwiftUI)

**Working name:** *CanvasSheets*  
**Platform:** macOS (targeting a new major release; “Tahoe” is acceptable)  
**Implementation:** Swift + SwiftUI (with AppKit where needed for performance)  
**Core differentiator:** A Numbers-like freeform canvas of multiple tables per sheet, with every interaction logged as a reproducible Python script that can recreate the entire document state.

---

## 1. Problem statement

Traditional spreadsheets (Excel/Calc) are great for quick numeric work and pivoting, but their “one big grid per sheet” layout makes it awkward to build dashboards and multi-table layouts. Numbers improves layout by allowing independent tables on a canvas, but gives up some power features and code-first reproducibility.

This project defines a macOS application that combines:
- **Numbers-style canvas layout** (many independent tables per sheet, freely positioned and sized),
- **Excel-like data entry and formulas** (fast and familiar),
- **A script-first audit trail** where UI actions append to a Python script,
- **A deterministic “rebuild-from-script” model**,
- **A workflow that lets users visually build logic, then refactor it into reusable Python functions**.

---

## 2. Goals and non-goals

### 2.1 Goals (must-have)

Mapped to your requirements (1–6):

1) **Numbers-like interaction model**
- Free creation of multiple independent tables on a sheet.
- Tables float on a canvas; the layout of one table does not constrain others.
- Direct typing in cells; copy/paste; fill handle; drag to move/resize tables.

2) **UI-to-Python action logging**
- Every user-visible action produces a corresponding Python statement appended to a script.
- Examples: add/move/resize table, set cell values, set formulas, rename sheet, create derived tables, etc.

3) **Adjustable label bands**
- Each table supports label regions on **top, left, bottom, right**.
- Users can increase/decrease label-band row/column counts and assign label text or references.

4) **NumPy-native data processing**
- Table bodies use the most efficient possible NumPy dtypes (float64/int64/bool/datetime64/etc.) whenever feasible.
- Mixed-type tables are supported, but the engine should store data **columnar and typed** as much as possible.

5) **Script determinism / rebuild**
- Re-running the accumulated Python script recreates the document state: sheets, tables, positions, styles, data, formulas, computed results.

6) **Inspectable and editable code**
- The Python script is viewable in-app in a dedicated “Code” surface.
- Users can edit the script, define functions, refactor repeated actions, and re-run to update the visual document.

### 2.2 Non-goals (explicitly out of scope for initial versions)

These can be added later, but are not required to ship an MVP:

- Full Excel file parity (all functions, VBA, exact formatting, macro compatibility).
- Multi-user real-time collaboration.
- Cloud sync (beyond iCloud Drive file storage).
- A full-fledged IDE/debugger (basic tracebacks and logs are enough).
- A giant BI feature set (PowerPivot, DAX, etc.).

---

## 3. Target users and use cases

### 3.1 Target users
- Analysts and engineers who want **quick spreadsheet-like iteration** but also **reproducible scripts**.
- “Power Numbers users” who love canvas layout but need more analysis tooling.
- People who want to “prototype visually” then **graduate to code** without rewriting from scratch.

### 3.2 Primary use cases
- Quick modeling: create multiple scratch tables on one canvas, link them with formulas.
- Data cleaning: import CSV, apply transforms, keep an audit trail in Python.
- Reporting: build a sheet that looks like a dashboard by placing multiple tables and charts.
- Repeatable workflows: extract a visually built sequence into a Python function and reuse it.

---

## 4. Product overview

### 4.1 High-level concept
A **document** contains **sheets** (tabs). Each sheet is a **canvas**. On the canvas are **objects**, primarily **tables**, **text boxes** and **charts** in later versions.

Every interaction is represented as a **Command**:
- A Command has a deterministic effect on the document model.
- A Command can be serialized into **Python source code**.
- Commands are appended to the document’s script (event log).

At any time, the document can be rebuilt by starting from an empty project and running the script from top to bottom.

---

## 5. Functional requirements

### 5.1 Document model
- The app is **document-based** (multiple windows/documents).
- File extension (example): `.nummern` (a package format).
- Each document contains:
  - **Sheets**: ordered list, each with a name and unique ID.
  - **Canvas objects**: tables (MVP), plus other objects.
  - **Python script** (primary source of truth for rebuild).
  - Optional: checkpoints/snapshots for faster open (see §10.4).

### 5.2 Sheets (tabs)
- Add, rename, reorder, delete sheets.
- Each sheet has an infinite (or very large) scrollable canvas.
- Canvas zoom (25%–400%).
- Snap-to-grid and alignment guides.

### 5.3 Tables on canvas
Tables are independent objects with:
- Unique, stable `table_id` (short, human-readable identifier like `table_1`).
- Name (user-facing).
- Geometry: `x`, `y`, `width`, `height` in canvas coordinates.
- Grid structure:
  - Body rows/cols.
  - Label bands: `top_label_rows`, `bottom_label_rows`, `left_label_cols`, `right_label_cols`.
- Styling (MVP: minimal but present):
  - font, number format, alignment, borders, fill color.
  - table header band styles can be distinct.

**Interactions:**
- Create table by clicking “Add Table” then dragging a rectangle, or default size.
- Move table by dragging its frame.
- Resize table with handles.
- Add/remove body rows/cols.
- Adjust label band counts independently (top/left/bottom/right).
- Direct edit cells.
- Copy/paste ranges, fill series, drag fill handle.
- Sort/filter (optional in v1; may be post-MVP).

### 5.4 Cell and range addressing
The app must support:
- A1-style addressing (e.g., `A1`, `B2:D20`).
- Addressing that includes label bands: treat labels as distinct address spaces (preferred, clearer).
- Use distinct regions to avoid ambiguity: `body[A1]`, `top_labels[A1]`, `left_labels[A1]`, etc.
- Provide convenience helpers for common patterns (e.g., “column label” = top label row 1).

### 5.5 Formulas
Support two formula modes:

#### 5.5.1 Spreadsheet formulas (default)
- User enters `=SUM(B2:B10)` style formulas.
- Support a core function library (MVP):
  - Arithmetic: `+ - * / ^`
  - Aggregates: `SUM, AVERAGE, MIN, MAX, COUNT, COUNTA`
  - Logical: `IF, AND, OR, NOT`
  - Lookup (v1): `XLOOKUP` or `VLOOKUP`, `INDEX/MATCH`
  - Date/time basics: `TODAY, NOW, DATE, YEAR, MONTH, DAY`
- Cell references can point to:
  - Same table ranges
  - Other tables (via table name or id)
- Relative/absolute references:
  - `A1`, `$A$1`, `A$1`, `$A1`

#### 5.5.2 Python formulas (advanced)
- User can opt-in per cell/range to use Python expression syntax, e.g.:
  - `py: np.log(body["Revenue"])`
  - `py: body[:, 3] * 1.2`
- The app provides a safe evaluation context (see §9.3).

#### 5.5.3 Recalculation model
- Maintain a dependency graph per table and across tables.
- Recalc triggers:
  - On cell commit
  - On formula change
  - On structure change (insert row/col)
- Performance:
  - Prefer vectorized evaluation over per-cell loops.
  - Allow “range formulas” (one formula producing a whole column).

### 5.6 Pivot tables / summaries
MVP can ship without full pivots, but v1 should include at least:
- Create **Summary Table** from a source table:
  - Choose row group keys, column group keys (optional), values + aggregation.
  - Aggregations: sum, mean, count, min, max.
- Output is a new table object, linked to source so it updates.
- This can be implemented with:
  - NumPy group-by strategies, or
  - Optional pandas for pivot-like operations (still NumPy-backed under the hood).

### 5.7 Import/export
MVP:
- Import CSV/TSV into a new table.
- Export table to CSV.
- Copy/paste from/to system clipboard.

v1:
- Import Excel (basic: values only; formulas optional).
- Export to Excel (values + formats where feasible).
- Import/Export Parquet for typed/large data.

### 5.8 Undo/redo
- Undo/redo must work for canvas actions and cell edits.
- The Command system should support inverse operations where feasible.
- Important: undo should also update the script view coherently.
  - Strategy: keep an **event log** and a **working head**; undo adds compensating commands or rewinds a transactional buffer (see §8.2).

---

## 6. Python event log requirements

### 6.1 Event log characteristics
- Append-only by default for UI-driven actions.
- Commands are grouped into **transactions** to avoid logging every keystroke.
  - Example: typing “123” logs one `set_cells(...)` at commit, not three.
- Each command is deterministic and order-dependent.
- There should be grouping of manual input. If someone fills a table with lots of data, one cell after the other, this should be consolidated in a command that fills all these together

### 6.2 Canonical Python API (DSL)
The script should use a stable internal API shipped with the app (a Python module bundled inside the app). Example module: `canvassheets_api`.

**Design principles:**
- **Stable IDs**: All objects referenced by `sheet_id` and `table_id` using short, human-readable identifiers (e.g., `sheet_1`, `table_1`).
- **Readable**: Users can understand and edit the script.
- **Composable**: Users can create functions, loops, and reuse logic.

### 6.3 Example generated script (illustrative)

```python
# ---- User code (editable) ---------------------------------------------
import numpy as np
from canvassheets_api import Project, Rect

def make_revenue_table(proj, sheet_id, x, y):
    t = proj.add_table(sheet_id, table_id="table_1",
                       name="Revenue", rect=Rect(x, y, 520, 260),
                       rows=20, cols=6,
                       labels=dict(top=1, left=1, bottom=0, right=0))
    t.set_top_labels(0, ["", "Q1", "Q2", "Q3", "Q4", "Total"])
    t.set_left_labels(0, [f"Week {i+1}" for i in range(20)])
    t.set_range("body[B1:E20]", 0.0, dtype="float64")
    t.set_formula("body[F1:F20]", "=SUM(B1:E1)")
    return t

# ---- Auto-generated log (append-only) --------------------------------
proj = Project()

sheet1 = proj.add_sheet("Tab1", sheet_id="sheet_1")
make_revenue_table(proj, "sheet_1", x=120, y=120)

proj.add_table("sheet_1", table_id="table_2", name="Inputs",
               rect=Rect(700, 120, 360, 220),
               rows=12, cols=4,
               labels=dict(top=1, left=1, bottom=0, right=0))

proj.table("table_2").set_cells({
    "body[B1]": 0.08,   # tax rate
    "left_labels[A1]": "Tax rate",
})

proj.table("table_1").set_formula("body[B1:E20]",
    "=B1*(1+Inputs::B1)"  # example cross-table ref
)

# ---- End of script ----------------------------------------------------
```

### 6.4 Script sections and edit policy
To enable user refactoring while keeping generated output reliable, the script should be structured into distinct regions:

1) **User code region** (free editing)
- Imports, helper functions, reusable transformations.

2) **Generated region** (append-only by default)
- The app writes commands here.
- The user may edit it, but the app warns on syntax errors and offers “Repair” by regenerating from internal history.

3) **Entrypoint region**
- The canonical execution entrypoint used for rebuild.

**Optional enhancement:** Store the command log internally as JSON and generate Python from it, but still ship the Python text. This improves safety (you can regenerate) while satisfying the “inspectable script” requirement.

---

## 7. Data model and typing

### 7.1 Table storage model (engine-level)
The engine should store table data in a form optimized for vectorized computation:

- **Columnar typed arrays** are preferred.
- For each table body column:
  - A NumPy array with a dtype (e.g., `float64`, `int64`, `datetime64[ns]`, `bool`).
- Missing values:
  - For floats: `np.nan`
  - For ints/bools: consider masked arrays or promote to float if needed, or use pandas nullable types if pandas is included.
- Strings:
  - Store as `object` arrays (MVP) or Arrow-backed strings (v1 for performance).

### 7.2 Type inference and coercion
- On import/paste and on cell entry, infer dtype per column.
- Coercion rules:
  - If a column starts numeric and a string appears, either:
    - Promote column to object, or
    - Keep numeric and treat invalid entries as missing with an error indicator.
- The UI must surface type conflicts unobtrusively (e.g., a small warning badge on the column).

### 7.3 Label bands storage
Label bands are separate 2D arrays (or per-band structures) storing:
- Strings
- Optional metadata (e.g., semantic role: “column name”, “units”, “category”).

---

## 8. Command system

### 8.1 Command pattern
All changes are represented as commands with:
- `command_id` (UUID)
- `timestamp`
- `payload`
- `apply(model)` (Swift-side)
- `serialize_to_python()` (engine-side or shared)
- Optional `invert()` for undo

Examples:
- `AddSheet(name, sheet_id)`
- `AddTable(sheet_id, table_id, rect, rows, cols, labels, name)`
- `MoveTable(table_id, rect)`
- `ResizeTable(table_id, rect)`
- `SetCells(table_id, cell_map)`
- `SetFormula(table_id, target_range, formula, mode)`
- `InsertRows(table_id, at, count)`
- `SetLabelBand(table_id, band, index, values)`
- `CreateSummaryTable(source_table_id, spec, output_table_id)`

### 8.2 Transaction grouping
Commands are grouped into transactions:
- “Edit cell” transaction: begins on start edit, ends on commit/blur.
- “Paste” transaction: a single `SetRange` rather than many `SetCell`.
- UI can display transactions in a history panel (optional).

### 8.3 Deterministic IDs
To support rebuild and cross-references, object IDs must be stable:
- When creating tables/sheets, generate short sequential IDs (e.g., `sheet_1`, `table_1`) immediately and include in script.
- The user-visible name can change without breaking references.

---

## 9. Python execution and security

### 9.1 Execution model
The system runs Python in a managed runtime:

- **Live session mode:** Maintain an in-memory Python interpreter and apply new commands incrementally.
- **Rebuild mode:** Restart interpreter, run the full script to reconstruct everything (used on open, and for “Run All”).

### 9.2 Process isolation (recommended)
Run Python in a separate process (helper) to improve stability and allow termination:
- Use XPC service (sandboxed) for:
  - executing commands
  - evaluating formulas
  - returning computed values / diffs
- The main app stays responsive even if Python code is slow.

### 9.3 Safety model for user code
Users can write arbitrary Python; this must be treated as potentially unsafe:
- Default mode: allow full Python but show a warning and require explicit user consent per document.
- Optional restricted mode:
  - Provide a limited execution context (no `os`, no file system writes, no network).
  - Enforce by running in a sandboxed helper with limited entitlements and potentially a restricted import policy.

At minimum:
- Document the security model clearly.
- Provide a “Reset Python state” button.
- Provide a “Run in Safe Mode” option.

---

## 10. Persistence format

### 10.1 Package layout (recommended)
Store documents as a package directory so users can inspect contents:

```
MyProject.canvassheets/
  project.json
  script.py
  history.json              (optional, internal command log)
  snapshots/
    latest.snapshot         (optional)
  assets/
    images/...
```

### 10.2 project.json
Contains:
- app version, schema version
- sheet list (ids + names)
- object list with ids and last-known geometry for quick load
- optional UI state (zoom, scroll positions)

### 10.3 script.py
Contains the Python source as described in §6.4.

### 10.4 Snapshot / checkpoint (optional but strongly recommended)
To make open fast for large files:
- Save a binary snapshot of computed arrays (e.g., `.npz` per table or Arrow IPC).
- On open:
  - Load snapshot immediately for display
  - Validate snapshot version/hash against script
  - Optionally re-run script in background-equivalent *within the same open action* (only if fast enough) or on-demand “Recompute”.

(If you want strict compliance with “recreate by rerunning script,” snapshots must be treated as an optimization, not the source of truth.)

---

## 11. UI/UX specification

### 11.1 Main window layout
- Toolbar:
  - Add Table
  - Add Sheet
  - Import
  - Run / Run All
  - Toggle Code Panel
  - Undo/Redo
- Sheet tab bar (top).
- Canvas (center).
- Right-side Inspector (optional):
  - Table properties (name, size, labels, formats)
  - Data type info
  - Formula help
- Bottom or side “Code” panel:
  - Script viewer/editor with syntax highlighting and line numbers
  - Console output / traceback panel

### 11.2 Table interaction details
- Selecting a table shows:
  - bounding box
  - resize handles
  - title bar with table name
- Double-click enters cell edit.
- Dragging:
  - moves table
  - with modifier key, duplicates table (optional)

### 11.3 Code panel behavior
- Two modes:
  1) **Read-only generated view** (safe default)
  2) **Editable script** (requires explicit “Unlock Editing”)
- Buttons:
  - Run Selection
  - Run All
  - Reset Runtime
- Errors:
  - Highlight line with error
  - Show traceback in console
  - Provide “Restore from history” if script becomes unparsable (if history.json exists)

### 11.4 Formula entry
- Formula bar similar to Excel.
- Autocomplete for function names.
- Click-to-reference: clicking cells inserts references into formula.

---

## 12. Performance requirements

### 12.1 Responsiveness targets
- Cell commit should update dependent values within:
  - < 50 ms for small tables (<10k cells)
  - < 200 ms for medium (100k cells) where possible
- Large tables should support:
  - virtualized rendering (only draw visible cells)
  - incremental computation and caching

### 12.2 Rendering strategy
SwiftUI alone is unlikely to be sufficient for high-performance grids.
Recommended:
- Use an AppKit-backed grid component:
  - `NSCollectionView` with custom layout, or
  - a dedicated grid renderer with layer-backed drawing
- Embed into SwiftUI via `NSViewRepresentable`.

### 12.3 Data transfer strategy
Avoid copying full arrays between Python and Swift repeatedly:
- Prefer:
  - requesting visible cell ranges only
  - caching displayed values
  - using shared memory buffers for numeric arrays when feasible (advanced)
- For MVP, prioritize correctness; optimize later with:
  - columnar caching
  - batch updates (“diffs” from engine)

---

## 13. Implementation architecture (Swift/SwiftUI)

### 13.1 Modules
1) **App/UI layer (SwiftUI)**
- Window, toolbar, sheet tabs, inspector, code panel.

2) **Document layer**
- `NSDocument`/SwiftUI document integration
- load/save package

3) **Model layer (Swift)**
- Sheets, Tables, geometry, user-visible state
- command queue and undo manager

4) **Command system**
- Command definitions
- transaction manager
- Python serialization

5) **Python Engine (separate process, recommended)**
- Embedded CPython runtime bundled with app
- NumPy (and optional pandas)
- Project API module (`canvassheets_api`)
- Evaluator for spreadsheet formulas → NumPy operations

6) **Bridge layer**
- XPC protocol definitions
- request/response types (JSON + binary blobs where needed)
- error handling and cancellation

### 13.2 Embedding Python
For distribution reliability:
- Bundle a specific CPython build with the app (universal binary).
- Bundle required wheels (NumPy, optionally pandas).
- Ensure code signing/notarization compatibility.
- Provide a controlled Python sys.path rooted in the app bundle and document package.

---

## 14. Formula engine design

### 14.1 Parsing
- Implement a spreadsheet formula parser in Swift **or** in Python.
- Recommendation:
  - Parse in Swift for immediate UI feedback (syntax errors, highlighting).
  - Compile to an intermediate representation (IR).
  - Execute IR via Python/NumPy for vectorized evaluation.

### 14.2 Cross-table references
Define a clear syntax, e.g.:
- `TableName::A1`
- `TableID::A1`
- `SheetName/TableName::A1` (optional)

Internally, resolve references to IDs.

### 14.3 Vectorization
Encourage column/range formulas:
- If a formula is applied to `F1:F20`, compile to a single vector expression rather than 20 scalar ones.

---

## 15. Editing-to-code mapping (examples)

### 15.1 Add a table
UI action:
- Add table on sheet “Tab1” at x=100,y=100

Command:
- `AddTable(sheet_id="sheet_1", table_id="table_1", rect=(100,100,520,260), rows=10, cols=6, labels=...)`

Python:
```python
proj.add_table("sheet_1", table_id="table_1",
               name="Table 1", rect=Rect(100, 100, 520, 260),
               rows=10, cols=6, labels=dict(top=1,left=1,bottom=0,right=0))
```

### 15.2 Edit cells
UI action:
- Paste a 10×4 block into body

Python:
```python
proj.table("table_1").set_range("body[A1:D10]", values_2d, dtype="float64")
```

### 15.3 Set a formula
UI action:
- User types `=SUM(B1:E1)` into column F

Python:
```python
proj.table("table_1").set_formula("body[F1:F20]", "=SUM(B1:E1)")
```

### 15.4 Move/resize table
Python:
```python
proj.table("table_1").set_rect(Rect(220, 120, 600, 280))
```

---

## 16. Error handling and diagnostics

### 16.1 Python errors
- Capture stdout/stderr and show in console panel.
- On exception:
  - Show traceback
  - Highlight offending line in code editor
  - Mark document as “out of sync” if runtime state is partially applied
  - Offer “Rebuild from top” button

### 16.2 Formula errors
- Display `#ERROR`, `#DIV/0!`, etc. in cells.
- Provide hover tooltip with underlying Python exception or parse error.

---

## 17. Accessibility and localization
- Full keyboard navigation for grids and canvas objects.
- VoiceOver support for table navigation (at least for headers and current cell).
- Localization-ready strings for UI and formula function names (optional; may start English-only for MVP).

---

## 18. Versioning and compatibility
- `project.json` schema versioning.
- Script API versioning:
  - The `canvassheets_api` module must remain backward compatible across app versions.
  - If breaking changes are needed, provide a migration step that rewrites script calls.

---

## 19. Milestones and scope

### 19.1 MVP (ship target)
- Document-based app
- Sheets with canvas
- Add/move/resize tables
- Editable grid with copy/paste
- Adjustable label bands
- Basic formula support (core functions)
- Command logging to Python script
- In-app code viewer + “Run All” rebuild
- Embedded Python + NumPy (minimal set)
- CSV import/export

### 19.2 v1
- Summary tables (pivot-like)
- Better formatting and number formats
- Cross-table references robust UI
- Snapshots for fast open
- Safer script editing workflow (history.json + regeneration)
- Chart objects (optional)

### 19.3 v2+
- Full pivot table UI
- Parquet/Arrow support
- Plugin system (Python packages per document)
- Collaboration

---

## 20. Open design decisions (to resolve early)
1) **Single source of truth:** script vs internal command log vs both.
   - Recommended: keep both; script is user-facing, JSON log is canonical for repair/regeneration.

2) **Formula parser location:** Swift vs Python.
   - Recommended: parse in Swift, execute in Python.

3) **Security posture:** unrestricted Python vs restricted mode by default.
   - Recommended: default to sandboxed helper + explicit consent for unrestricted scripting.

4) **Data interchange format:** direct PythonKit calls vs XPC process.
   - Recommended: XPC process for stability and killability.

5) **Pivot implementation:** NumPy-only vs optional pandas.
   - Recommended: ship pandas optionally for v1 if it materially improves pivots and groupby ergonomics.

---

## 21. Acceptance criteria (definition of done)

A document must be considered correct when:
- A user can create a sheet, add multiple tables, move/resize them, enter values and formulas, and see results update.
- The script view shows appended Python statements corresponding to actions.
- Closing and reopening the document produces the same layout and computed values.
- Deleting all runtime state and re-running the script recreates the project without manual intervention.
- The user can define a Python function in the code panel, call it from the generated region, and the UI reflects the result.

---

## Appendix A: Proposed minimal Python API surface

```python
class Project:
    def add_sheet(self, name: str, sheet_id: str): ...
    def add_table(self, sheet_id: str, table_id: str, name: str, rect, rows: int, cols: int, labels: dict): ...
    def table(self, table_id: str) -> "Table": ...

class Table:
    def set_rect(self, rect): ...
    def resize(self, rows: int = None, cols: int = None): ...
    def set_labels(self, top=None, left=None, bottom=None, right=None): ...
    def set_cells(self, mapping: dict): ...
    def set_range(self, range_str: str, values, dtype: str = None): ...
    def set_formula(self, target_range: str, formula: str, mode: str = "spreadsheet"): ...
    def to_numpy(self): ...
```

---

## Appendix B: Suggested Swift types (sketch)

- `ProjectDocument: NSDocument`
- `SheetModel { id: String, name: String, objects: [CanvasObject] }`
- `TableModel: CanvasObject { id: String, name: String, rect: CGRect, gridSpec: GridSpec, ... }`
- `Command` protocol + concrete command structs
- `PythonEngineClient` (XPC client) + `PythonEngineService` (helper)

---

*End of specification.*
