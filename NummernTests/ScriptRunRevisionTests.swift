import XCTest
@testable import Nummern

final class ScriptRunRevisionTests: XCTestCase {
    func testTokenMatchesUntilBumped() {
        var revision = ScriptRunRevision()
        let token = revision.token()

        XCTAssertTrue(revision.matches(token))

        revision.bump()
        XCTAssertFalse(revision.matches(token))
    }

    func testTokenReflectsLatestValue() {
        var revision = ScriptRunRevision()
        revision.bump()
        revision.bump()

        let token = revision.token()

        XCTAssertTrue(revision.matches(token))
        XCTAssertEqual(token, 2)
    }
}
