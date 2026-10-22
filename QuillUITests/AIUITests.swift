import XCTest

/// Einstellungen › KI (16.1, ADR-032). Statt Apple Intelligence ein Test-Modell
/// (`-QuillFakeAI`, nur Debug und Test-Store), damit der Test auf jedem Mac gleich läuft.
@MainActor
final class AIUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        app?.terminate()
    }

    private func launch(availability: String) {
        app = XCUIApplication.quill()
        app.launchArguments += ["-QuillFakeAI", availability]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.typeKey(",", modifierFlags: .command)
        app.toolbars.buttons["KI"].click()
    }

    func testTurnOffAI() throws {
        launch(availability: "available")
        let toggle = app.descendants(matching: .any)["settings.aiEnabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertEqual(toggle.value as? Int, 1, "Standard: an")
        XCTAssertFalse(app.descendants(matching: .any)["settings.aiUnavailable"].exists)
        toggle.click()
        waitFor((toggle.value as? Int) == 0, "KI nicht ausgeschaltet")
    }

    func testExplainsMissingAppleIntelligence() throws {
        launch(availability: "appleIntelligenceNotEnabled")
        let reason = app.descendants(matching: .any)["settings.aiUnavailable"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        let text = reason.label + (reason.value as? String ?? "")
        XCTAssertTrue(text.contains("Apple Intelligence ist aus"), text)
        XCTAssertFalse(app.descendants(matching: .any)["settings.aiEnabled"].exists, "Ohne Modell kein Schalter")
    }

    private func waitFor(_ condition: @autoclosure @escaping () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, message, file: file, line: line)
    }
}
