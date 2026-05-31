import XCTest
@testable import Nummern

final class InteractionTests: XCTestCase {
    // MARK: KeyboardNavigator

    func testNavigationMovesAndClamps() {
        expect(.down, from: (1, 1), equals: (2, 1))
        expect(.enter, from: (1, 1), equals: (2, 1))
        expect(.right, from: (1, 1), equals: (1, 2))
        expect(.up, from: (0, 0), equals: (0, 0))       // clamps at top
        expect(.down, from: (3, 3), equals: (3, 3))     // clamps at bottom
        expect(.backTab, from: (2, 0), equals: (2, 0))  // clamps at left
    }

    private func expect(_ key: KeyboardNavigator.Key, from: (Int, Int), equals: (Int, Int),
                        file: StaticString = #file, line: UInt = #line) {
        let result = KeyboardNavigator.move(from: (from.0, from.1), key: key, rows: 4, cols: 4)
        XCTAssertEqual(result.row, equals.0, file: file, line: line)
        XCTAssertEqual(result.col, equals.1, file: file, line: line)
    }

    // MARK: CSVCodec

    func testCSVEncodeQuoting() {
        let block: [[CellValue]] = [
            [.string("a"), .string("b,c"), .number(1)],
            [.string("quote\"d"), .empty, .string("line\nbreak")],
        ]
        let csv = CSVCodec.encode(block)
        XCTAssertEqual(csv, "a,\"b,c\",1\n\"quote\"\"d\",,\"line\nbreak\"")
    }

    func testCSVRoundTripThroughClipboardParser() {
        let block: [[CellValue]] = [[.string("Region"), .string("Sales")],
                                    [.string("North"), .number(10)]]
        let csv = CSVCodec.encode(block)
        XCTAssertEqual(ClipboardParser.parse(csv), block)
    }

    func testBodyBlockTrimsToContent() throws {
        let json = """
        {"id":"t","name":"t","rect":{"x":0,"y":0,"w":0,"h":0},
         "grid":{"rows":4,"cols":4,"labels":{"top":0,"left":0,"bottom":0,"right":0}},
         "columns":[],"body":[[1,2,null,null],[3,null,null,null],[null,null,null,null],[null,null,null,null]],
         "labels":{"top":[],"left":[],"bottom":[],"right":[]}}
        """
        let table = try JSONDecoder().decode(TableSnapshot.self, from: Data(json.utf8))
        let block = CSVCodec.bodyBlock(table)
        XCTAssertEqual(block.count, 2)          // rows 0..1 have content
        XCTAssertEqual(block[0].count, 2)       // cols 0..1 have content
    }

    // MARK: undo / redo

    func testUndoRedoTracksCommandLog() {
        let document = NummernDocument()        // starts with one sheet
        let manager = UndoManager()
        document.undoManager = manager

        let before = document.log.commands.count
        manager.beginUndoGrouping()
        document.addTable()
        manager.endUndoGrouping()
        XCTAssertEqual(document.log.commands.count, before + 1)

        manager.undo()
        XCTAssertEqual(document.log.commands.count, before)

        manager.redo()
        XCTAssertEqual(document.log.commands.count, before + 1)
    }
}
