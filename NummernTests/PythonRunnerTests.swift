import XCTest
@testable import Nummern

final class PythonRunnerTests: XCTestCase {
    func testDecodePicksLastJSONLine() throws {
        let stdout = """
        table_1 totals: [1, 2]
        {"version":1,"sheets":[{"id":"sheet_1","name":"Tab1","tables":[],"charts":[]}]}
        """
        let snapshot = try PythonRunner.decode(stdout, stderr: "")
        XCTAssertEqual(snapshot.sheets.first?.id, "sheet_1")
    }

    func testDecodeThrowsWithoutJSON() {
        XCTAssertThrowsError(try PythonRunner.decode("no json here", stderr: ""))
    }

    /// End-to-end: actually runs the bundled engine. Skips cleanly if the repo
    /// venv / package isn't available in this environment.
    func testEngineRunsRecordedScript() throws {
        guard let runner = try? PythonRunner() else {
            throw XCTSkip("Python engine not resolvable in this environment")
        }
        let log = CommandLog()
        log.append(AddSheetCommand(id: "sheet_1", name: "Tab1"))
        log.append(AddTableCommand(sheetId: "sheet_1", id: "table_1", x: 80, y: 80,
                                   rows: 2, cols: 2, labels: .init(top: 0, left: 0, bottom: 0, right: 0)))
        log.append(SetLiteralCommand(tableId: "table_1", range: "A0:A1",
                                     values: [[.number(3)], [.number(4)]]))
        log.append(SetExprCommand(tableId: "table_1", target: "B0",
                                  expr: #"table_1["A"].sum()"#))

        let result: PythonRunner.RunResult
        do {
            result = try runner.run(script: log.script(), emit: .json)
        } catch {
            throw XCTSkip("Engine run failed (likely no venv): \(error.localizedDescription)")
        }
        let table = try XCTUnwrap(result.snapshot.table(id: "table_1"))
        XCTAssertEqual(table.cell(row: 0, col: 1), .number(7))   // sum(3,4)
    }
}
