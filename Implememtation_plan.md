# Implementation Plan: CanvasSheets (macOS Swift/SwiftUI + Python)

This plan is sequenced so every step ships a testable increment. Each step lists the unit tests to add/run. The plan targets the MVP in the spec, then extends to v1 items that are explicitly called out.

Testing conventions assumed:
- Swift: XCTest in the app test target.
- Python: pytest for the bundled `canvassheets_api` module.
- After each step, run `python -m pytest -k "formula_sugar or export_numpy"` and `xcodebuild test -scheme Nummern -destination 'platform=macOS'`.

---

## Step 0: Xcode project scaffold (completed)

Deliverable:
- Create a macOS SwiftUI DocumentGroup app target (FileDocument-based).
- Register the `.nummern` UTType and document type in Info.plist with bundle ID `com.digitalhandstand.nummern`.
- Switch the document to a package-based FileWrapper with `project.json` and `script.py` stubs.
- Add a minimal placeholder UI and a unit test target.
- Add XcodeGen project definition for reproducible project generation.
- Enable generated asset symbol extensions in build settings (Xcode recommended).

Testable increment:
- The app opens, creates, saves, and reopens a `.nummern` document package with placeholder `project.json` and `script.py`.

Unit tests to add/run:
- None (scaffold only).

Status:
- [x] Completed

---

## Step 1: Core domain model and IDs (Swift)

Deliverable:
- Define core model types with stable IDs and geometry: `ProjectModel`, `SheetModel`, `TableModel`, `CanvasObject`, `GridSpec`, `LabelBands`, `Rect`.
- Implement consistent ID creation (short sequential IDs like `sheet_1` and `table_1`) and name handling.
- Add a minimal `ProjectStore` with in-memory state and mutation APIs.

Testable increment:
- The app can create a project with a sheet and table in memory and query geometry/labels.

Unit tests to add/run:
- `ProjectModelTests.testStableIdsPersistOnRename()`
- `TableModelTests.testGridSpecDefaults()`
- `TableModelTests.testRectMutation()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/ProjectModelTests`

Status:
- [x] Completed

---

## Step 2: Command system + Python serialization (Swift)

Deliverable:
- Implement `Command` protocol with `apply(model)`, `invert()`, and `serializeToPython()`.
- Add concrete commands: `AddSheet`, `RenameSheet`, `AddTable`, `SetTableRect`, `ResizeTable`, `SetCells`, `SetRange`, `SetLabelBand`, `SetFormula`, `InsertRows`, `InsertCols`.
- Implement a `TransactionManager` that groups commands and produces a Python log string.

Testable increment:
- Applying commands mutates the model; a deterministic Python script is generated for the same command sequence.

Unit tests to add/run:
- `CommandApplyTests.testAddSheetAndAddTable()`
- `CommandSerializationTests.testPythonOutputDeterminism()`
- `TransactionManagerTests.testEditCellGroupsIntoSingleTransaction()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/CommandSerializationTests`

Status:
- [x] Completed

---

## Step 3: Document package persistence (Swift)

Deliverable:
- Expand the existing SwiftUI DocumentGroup `.nummern` package implementation.
- Replace the placeholder `project.json` with the real model + layout schema.
- Read/write `project.json` (model + layout), `script.py` (generated Python), and optional `history.json` (raw commands).
- On open: load `project.json` into the model and load `script.py` for the code panel.

Testable increment:
- A document can be created, saved, closed, and reopened with the same sheets/tables and script.

Unit tests to add/run:
- `ProjectPersistenceTests.testEncodeDecodeProjectJson()`
- `ProjectPersistenceTests.testPackageLayout()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/ProjectPersistenceTests`

Status:
- [x] Completed

---

## Step 4: Canvas UI with tables (SwiftUI + AppKit)

Deliverable:
- Implement window layout (toolbar, sheet tabs, canvas, optional inspector).
- Render tables as draggable/resizable canvas objects (frame only) using SwiftUI + NSViewRepresentable where needed.
- Wire Add Sheet/Add Table actions to commands and event log.
- Canvas auto-sizes to the visible window or to fit all tables, whichever is larger.
- Table sizing snaps to grid footprint; resize adds/removes body rows/cols and snaps on release.
- Inspector includes body row/column controls alongside label bands.

Testable increment:
- Users can add a sheet, add a table, move/resize it, and see Python log updates.

Unit tests to add/run:
- `CanvasViewModelTests.testMoveTableUpdatesModelAndLogsCommand()`
- `CanvasViewModelTests.testResizeTableUpdatesRect()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/CanvasViewModelTests`

Status:
- [x] Completed

---

## Step 5: Grid rendering + address parsing (AppKit-backed grid)

Deliverable:
- Implement an AppKit-backed grid view for table bodies with virtualization.
- Implement address and range parsing for `body[A0]`, `top_labels[A0]`, `left_labels[A0]`, etc. (0-based rows).
- Add coordinate mapping between grid indices and address strings.

Testable increment:
- A table shows a scrollable grid; address parsing resolves to correct indices and bands.

Unit tests to add/run:
- `RangeParserTests.testBodyAddress()`
- `RangeParserTests.testLabelBandAddress()`
- `GridIndexingTests.testVisibleRangeMapping()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/RangeParserTests`

Status:
- [x] Completed

---

## Step 6: Cell editing, label bands, and clipboard (Swift)

Deliverable:
- Enable direct cell editing for body and label bands.
- Allow formulas to target label-band cells (top/left/bottom/right) for summaries.
- Implement copy/paste parsing and `SetRange` command aggregation.
- Implement label band size adjustments (top/left/bottom/right).
- Implement column typing inference metadata in the model (numeric vs string) for body columns.
- Improve formula editing UX: click/drag to insert cell/range references (including cross-table click insertion), drag selection rectangle, color-coded reference highlights (grid + formula text), cross-table highlights, widened inline editor for long formulas, and Enter/Escape commit/cancel behavior (clicking other cells inserts references instead of committing).
- Keep SwiftUI API usage current (e.g., macOS 14+ `onChange` signatures).

Testable increment:
- Users can edit cells, paste ranges, and edit label bands with logged Python commands; formula editing shows references and highlights while composing.

Unit tests to add/run:
- `CellEditTests.testSetRangePopulatesCellValues()`
- `LabelBandTests.testAdjustLabelBandCounts()`
- `TypeInferenceTests.testColumnPromotesToStringOnText()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/LabelBandTests`

Status:
- [x] Completed

---

## Step 7: Python API module + engine bridge (moved earlier)

Deliverable:
- Implement `canvassheets_api` in Python with `Project` and `Table` classes supporting:
  - `add_sheet`, `add_table`, `set_rect`, `resize`, `set_labels`, `set_cells`, `set_range`, `set_formula`.
- Add `table_context`, `label_context`, and `formula()` helpers for readable script logging.
- Support array-style `t[row, col]` indexing (0-based rows) for body cell reads/writes in Python scripts.
- Canonicalize row numbering to 0-based across Swift and Python (`A0` is the first row; `t[0, 0]` maps to `A0`).
- Allow `add_table` to accept `x`/`y` with grid-derived width/height (rect remains supported).
- Add a Swift `PythonEngineClient` that runs the script in a Python process and returns a reconstructed `ProjectModel`.
- Ensure the engine can execute the script end-to-end and return a project (formula translation/execution lands in Step 9).
- Add a repo-level virtualenv (`.venv`) workflow with pinned `requirements.txt`, and prefer that venv when launching Python.
- Future: bundle a universal2 Python interpreter + stdlib inside the app bundle and point the engine at it for distribution.

Testable increment:
- Running the generated script reconstructs tables and returns a `ProjectModel` derived from Python output.

Unit tests to add/run:
- Swift: `PythonBridgeTests.testRunScriptBuildsTables()`
- Run: `RUN_PYTHON_BRIDGE_TESTS=1 xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/PythonBridgeTests`

Status:
- [x] Completed

---

## Step 8: Table naming alignment (IDs as labels)

Deliverable:
- Use `table_id` as the visible label in the model and UI (no custom table names in MVP).
- Ensure script references and UI labels always match the table ID.
- Reserve a display-name field for future use (not shown in UI yet).

Testable increment:
- New tables show their ID (e.g., `table_1`) in the canvas title bar and inspector.

Unit tests to add/run:
- `TableNamingTests.testTableNameDefaultsToId()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/TableNamingTests`

Status:
- [x] Completed

---

## Step 9: Formula syntax + translation to Python (MVP)

Deliverable:
- Define spreadsheet formula grammar and reference syntax (default region is `body`, cross-table references use `table_id`, rows are 0-based).
- Implement translation to Python helper expressions (`cell`, `col`, `rng`, `set_cell`, `set_col`, `set_range`, `cs_*`).
- Add formula helper DSL functions in Python (`c_sum`, `c_avg`, `c_min`, `c_max`, `c_count`, `c_counta`, `c_range`, plus logical helpers `c_if`, `c_and`, `c_or`, `c_not`) and use them in generated logs for simple aggregate formulas.
- Support cell-level formulas and range formulas with relative reference expansion.
- Generate Python formula expressions after data writes during script generation.
- Log body edits in `table_context` blocks; label-band value edits in `label_context` blocks; label-band formulas use region proxies inside `table_context` (e.g., `top_labels.a0 = c_sum('a0:a9')`).
- Collapse consecutive `t = proj.table(...)` + context blocks into a single block for readability.
- Hoist body data edits into a dedicated `table_context` block immediately after each `add_table` call, while leaving formula blocks append-only in chronological order.
- Inline cross-table cell references in formulas using `table_id.A0` sugar, with `table_id = proj.table("table_id")` aliases emitted after each `add_table`.
- Accept dot-prefixed cross-table references (`table_id.A0`, `table_id.top_labels[A0]`) in spreadsheet formulas and highlight/insert them in the editor.
- Evaluate formulas once in global log order (recorded at set time) across tables so dependencies match script order.

Testable increment:
- Entering a spreadsheet formula produces readable Python expressions in the script, and rerunning the script updates computed values (data blocks appear right after `add_table`).

Unit tests to add/run:
- Python: `canvassheets_api/tests/test_formula_translation.py`
- Python: `canvassheets_api/tests/test_formula_sugar.py`
- Python: `canvassheets_api/tests/test_formula_sugar.py::test_cross_table_formula_order`
- Python: `canvassheets_api/tests/test_formula_sugar.py::test_formula_helper_aggregates`
- Python: `canvassheets_api/tests/test_formula_sugar.py::test_formula_helper_logical`
- Swift: `PythonLogNormalizerTests.testMergesConsecutiveFormulaContextBlocks()`
- Run: `python -m pytest -k "formula_translation or formula_sugar"`

Status:
- [x] Completed

---

## Step 10: Bugs from ChatGPT Pro review (critical/high/medium)

Deliverable:
- Python: add `Project.rename_sheet(sheet_id, new_name)` (or stop emitting it in Swift).
- Python: fix JSON export for `numpy.bool_` in `_cell_value_to_json`.
- Swift: preserve user code when script markers are missing/edited (tolerate whitespace/prefixes).
- Swift: escape `\n`, `\r`, `\t`, and control chars in `PythonLiteralEncoder.encodeString`.
- Swift: drain Python stdout/stderr while the process runs to avoid pipe deadlocks (cap output).
- Swift: normalize `set_range('body[...]')` by stripping quotes in `PythonLogNormalizer`.
- Python: keep `Table.rect` consistent after `set_labels/insert_rows/insert_cols`.
- Swift: commit non-formula edits on selection change (formula edits still insert references).

Testable increment:
- Script round-trips are resilient (no user-code loss, no Python hang, no rename errors), JSON export handles numpy booleans, and range hoisting works for quoted `set_range` calls.

Unit tests to add/run:
- Python: `test_project_rename_sheet()` (add_sheet then rename then assert `to_dict()`).
- Python: `test_json_export_handles_numpy_bool()` (json.dumps on `proj.to_dict()` after assigning `np.bool_`).
- Python: `test_rect_updates_after_resize_and_labels()` (labels/rows/cols adjust rect size).
- Swift: `ScriptComposerTests` (preserve user region, tolerate whitespace, preserve full script if markers missing).
- Swift: `PythonLiteralEncoderTests` (encode strings with newlines/tabs/control chars).
- Swift: `PythonLogNormalizerTests` (quoted `set_range('body[...]')` is hoisted).
- Swift/UI: selection-commit test for non-formula edits (UI or unit-level if possible).

Status:
- [x] Completed

---

## Step 11: Rebuild-from-script + code panel

Deliverable:
- Implement code panel with user/generated/entrypoint sections.
- Add Run Selection/Run All/Reset Runtime controls.
- On Run All: restart Python engine, run full script, update model and grid display.
- Implement error mapping to line numbers and console display.
- MVP update: event log is no longer a separate UI panel; Python log output is sent to the developer console.
- When running a script, parse the generated log section and store it as command history so subsequent edits append to the script that was just run.
- Strip table alias lines (`table_id = proj.table(...)`) when rebuilding history from the generated region to prevent duplicate aliases.

Testable increment:
- Editing user code and running the script updates the document; errors surface in the panel.

Unit tests to add/run:
- `ScriptSectionTests.testRoundTripPreservesUserRegion()`
- `RunAllTests.testRebuildMatchesModelState()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/ScriptSectionTests`

Status:
- [ ] In progress (script editor + Run Script + auto-run + error alert done; Run Selection/Reset Runtime + error mapping pending)

---

## Step 11a: Portable NumPy export (completed)

Deliverable:
- Add `export_numpy_script(project, include_labels=True, include_formulas=False)` in Python to emit a portable export script.
- When `include_formulas=False`, export a standalone NumPy-only script with `tables` arrays (and optional labels).
- When `include_formulas=True`, rebuild the project via `canvassheets_api` (add tables, `set_cells`, then `set_formula`), apply formulas, and emit `tables` arrays plus a `formulas` entry.
- Prefer numeric `dtype=float` when all values are numeric; otherwise fall back to `dtype=object`.
- Add a UI action that writes the export script to a user-chosen `.py` file.

Testable increment:
- Exported script yields correct arrays; formula-aware export recomputes values from the stored formulas.

Unit tests to add/run:
- Python: `canvassheets_api/tests/test_export_numpy.py`
- Run: `python -m pytest -k export_numpy`

Status:
- [x] Completed

---

## Step 12: Undo/redo and transaction coherence

Deliverable:
- Integrate `UndoManager` with command transactions.
- Implement `invert()` for core commands (table move/resize, set range, insert rows/cols, label edits).
- Ensure undo/redo updates both model and Python log coherently.

Testable increment:
- Undo/redo reverts visual changes and updates the script consistently.

Unit tests to add/run:
- `UndoRedoTests.testUndoMoveTable()`
- `UndoRedoTests.testUndoSetRange()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/UndoRedoTests`

---

## Step 13: CSV import/export (Swift + Python)

Deliverable:
- Implement CSV import into a new table with dtype inference.
- Implement CSV export from a selected table.
- Integrate clipboard copy/paste with CSV semantics.

Testable increment:
- Import a CSV into a table and export back with matching content.

Unit tests to add/run:
- `CSVImportTests.testInferTypesOnImport()`
- `CSVExportTests.testExportMatchesSource()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/CSVImportTests`

---

## Step 14: Summary tables (v1 feature)

Deliverable:
- Implement `CreateSummaryTable` command and UI flow.
- Add Python-side summary computation (NumPy group-by or optional pandas) and update propagation.

Testable increment:
- Creating a summary table updates when source data changes.

Unit tests to add/run:
- `SummaryTableTests.testAggregationSum()`
- `SummaryTableTests.testUpdatesOnSourceChange()`
- Run: `python3 -m pytest canvassheets_api/tests -k summary` and `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/SummaryTableTests`

---

## Step 15: Snapshot caching (optional but recommended)

Deliverable:
- Save/load snapshots for faster open (`snapshots/latest.snapshot`).
- Validate snapshot compatibility with script hash; fallback to script when mismatched.

Testable increment:
- Large documents load with snapshot; results match a full rebuild.

Unit tests to add/run:
- `SnapshotTests.testLoadMatchesScriptRebuild()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/SnapshotTests`

---

## Step 16: Polishing, performance, and accessibility

Deliverable:
- Virtualized grid performance improvements (range-based rendering and diff updates).
- Keyboard navigation and VoiceOver labels for the grid and table headers.
- UI refinements for formula bar, autocomplete, and error badges.

Testable increment:
- Smooth scrolling on mid-size tables and basic keyboard navigation.

Unit tests to add/run:
- `GridPerformanceTests.testVisibleRangeDiffing()`
- `AccessibilityTests.testTableHeaderLabels()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/AccessibilityTests`

---

## Definition of Done Checkpoints

- MVP complete after Step 13.
- v1 core feature complete after Step 14.
- Optional performance snapshot complete after Step 15.

---

## TODO bucket (future)

- Add display names for sheets/tables (UI-only; references remain ID-based).
