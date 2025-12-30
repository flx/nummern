# Implementation Plan: CanvasSheets (macOS Swift/SwiftUI + Python)

This plan is sequenced so every step ships a testable increment. Each step lists the unit tests to add/run. The plan targets the MVP in the spec, then extends to v1 items that are explicitly called out.

Testing conventions assumed:
- Swift: XCTest in the app test target.
- Python: pytest for the bundled `canvassheets_api` module.

---

## Step 0: Xcode project scaffold (completed)

Deliverable:
- Create a macOS SwiftUI DocumentGroup app target (FileDocument-based).
- Register the `.nummern` UTType and document type in Info.plist with bundle ID `com.digitalhandstand.nummern`.
- Switch the document to a package-based FileWrapper with `project.json` and `script.py` stubs.
- Add a minimal placeholder UI and a unit test target.
- Add XcodeGen project definition for reproducible project generation.

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
- Implement address and range parsing for `body[A1]`, `top_labels[A1]`, `left_labels[A1]`, etc.
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
- Implement copy/paste parsing and `SetRange` command aggregation.
- Implement label band size adjustments (top/left/bottom/right).
- Implement column typing inference metadata in the model (numeric vs string) for body columns.

Testable increment:
- Users can edit cells, paste ranges, and edit label bands with logged Python commands.

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
- Add a Swift `PythonEngineClient` that runs the script in a Python process and returns a reconstructed `ProjectModel`.
- Ensure the engine can execute formulas in Python once dependencies are known (evaluation can be stubbed initially).
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

## Step 8: Formula dependency parsing and graph (Swift)

Deliverable:
- Implement a lightweight Swift parser to extract references from formulas (no evaluation).
- Build a dependency graph per table and across tables.
- Implement recalculation scheduling on cell edits and structural changes.

Testable increment:
- Entering `=SUM(B1:E1)` updates dependencies and triggers a recalculation event (execution stays in Python).

Unit tests to add/run:
- `FormulaParserTests.testSimpleAggregate()`
- `DependencyGraphTests.testCrossTableReference()`
- `DependencyGraphTests.testRowInsertInvalidatesReferences()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/FormulaParserTests`

---

## Step 9: Rebuild-from-script + code panel

Deliverable:
- Implement code panel with user/generated/entrypoint sections.
- Add Run Selection/Run All/Reset Runtime controls.
- On Run All: restart Python engine, run full script, update model and grid display.
- Implement error mapping to line numbers and console display.

Testable increment:
- Editing user code and running the script updates the document; errors surface in the panel.

Unit tests to add/run:
- `ScriptSectionTests.testRoundTripPreservesUserRegion()`
- `RunAllTests.testRebuildMatchesModelState()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/ScriptSectionTests`

---

## Step 10: Undo/redo and transaction coherence

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

## Step 11: CSV import/export (Swift + Python)

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

## Step 12: Summary tables (v1 feature)

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

## Step 13: Snapshot caching (optional but recommended)

Deliverable:
- Save/load snapshots for faster open (`snapshots/latest.snapshot`).
- Validate snapshot compatibility with script hash; fallback to script when mismatched.

Testable increment:
- Large documents load with snapshot; results match a full rebuild.

Unit tests to add/run:
- `SnapshotTests.testLoadMatchesScriptRebuild()`
- Run: `xcodebuild test -scheme Nummern -destination 'platform=macOS' -only-testing:NummernTests/SnapshotTests`

---

## Step 14: Polishing, performance, and accessibility

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

- MVP complete after Step 11.
- v1 core feature complete after Step 12.
- Optional performance snapshot complete after Step 13.
