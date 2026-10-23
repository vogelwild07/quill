import XCTest

/// Einstellungen › Spotlight (15.2, ADR-033). Test-Stores schreiben nur in einen Index im
/// Speicher, nie in den des Macs; was dort ankommt, prüfen die Unit-Tests.
@MainActor
final class SpotlightUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.quill()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws {
        app?.terminate()
    }

    func testTurnSpotlightOnAndOff() throws {
        app.typeKey(",", modifierFlags: .command)
        app.toolbars.buttons["Spotlight"].click()
        let toggle = app.descendants(matching: .any)["settings.spotlight"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? Int, 0, "Standard: aus")

        toggle.click()
        waitFor((toggle.value as? Int) == 1, "Spotlight nicht eingeschaltet")
        app.typeKey("w", modifierFlags: .command)
        app.typeKey(",", modifierFlags: .command)
        app.toolbars.buttons["Spotlight"].click()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? Int, 1, "Wahl nach dem Schließen der Einstellungen vergessen")

        toggle.click()
        waitFor((toggle.value as? Int) == 0, "Spotlight nicht ausgeschaltet")
        app.typeKey("w", modifierFlags: .command)
    }

    private func waitFor(_ condition: @autoclosure @escaping () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, message, file: file, line: line)
    }
}
