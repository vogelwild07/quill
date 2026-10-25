import XCTest

/// Updates (ADR-037): Schalter aus heißt keine Anfrage, Frage beim ersten Start, Menü
/// „Nach Updates suchen …“ und Einstellungen › Allgemein. Statt GitHub fragt Quill nur
/// `UpdateTestServer` auf 127.0.0.1 (`-QuillUpdateTestFeed`, nur Debug und Test-Store);
/// dessen Versionsliste ist unsigniert und muss abgelehnt werden. Einstellungen nur im
/// Speicher, nie die des Macs.
@MainActor
final class UpdateUITests: XCTestCase {
    private var app: XCUIApplication!
    private var server: UpdateTestServer!

    override func setUp() async throws {
        continueAfterFailure = false
        server = try UpdateTestServer()
    }

    override func tearDown() async throws {
        app?.terminate()
        server = nil
    }

    func testSwitchedOffMeansNoRequest() throws {
        launch(try feed() + ["-QuillTestUpdateAutomatic", "NO"])
        // Quill prüft beim Start und dann stündlich, ob eine Suche fällig ist.
        idle(8)
        XCTAssertEqual(server.requests, 0, "Anfrage trotz ausgeschaltetem Schalter")

        app.typeKey(",", modifierFlags: .command)
        let toggle = app.descendants(matching: .any)["settings.updates.automatic"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Einstellungen › Allgemein nicht offen")
        XCTAssertEqual(toggle.value as? Int, 0, "Standard: aus")
        XCTAssertEqual(text(app.descendants(matching: .any)["settings.updates.lastChecked"]), "Noch nie")
        toggle.click()
        waitFor(self.server.requests >= 1, "Keine Anfrage nach dem Einschalten")
        // Höchstens einmal am Tag; im Hintergrund still, auch wenn Quill die Liste ablehnt.
        idle(5)
        XCTAssertEqual(server.requests, 1, "Mehr als eine Anfrage")
        XCTAssertFalse(app.windows["Update"].exists, "Suche im Hintergrund zeigt ein Fenster")
        XCTAssertEqual(text(app.descendants(matching: .any)["settings.updates.lastChecked"]), "Noch nie",
                       "Unsignierte Versionsliste als geprüft gezählt")
    }

    func testSwitchedOnChecksAtLaunch() throws {
        launch(try feed() + ["-QuillTestUpdateAutomatic", "YES"])
        waitFor(self.server.requests >= 1, "Keine Anfrage beim Start trotz eingeschaltetem Schalter")
    }

    func testMenuCheckRejectsUnsignedList() throws {
        launch(try feed())
        app.menuBars.menuBarItems["Quill"].click()
        app.menuBars.menuItems["Nach Updates suchen …"].click()
        let window = app.windows["Update"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Fenster „Update“ fehlt")
        let title = window.staticTexts["update.title"]
        waitFor(self.text(title) == "Update nicht möglich", "Unsignierte Versionsliste nicht abgelehnt")
        XCTAssertTrue(text(window.staticTexts["update.message"]).contains("Signatur"), text(window.staticTexts["update.message"]))
        XCTAssertEqual(server.requests, 1)
        window.buttons["update.ok"].click()
        waitFor(!window.exists, "Fenster bleibt nach „OK“")
    }

    func testMenuItemOffWithoutTestServer() throws {
        launch([])
        app.menuBars.menuBarItems["Quill"].click()
        let item = app.menuBars.menuItems["Nach Updates suchen …"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertFalse(item.isEnabled, "Test-Store ohne Testserver darf nicht suchen")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testFirstLaunchQuestion() throws {
        // Standard (Return): nicht suchen.
        launch(try feed() + ["-QuillTestUpdateAsk", "YES"])
        let no = app.buttons["updatePrompt.no"]
        XCTAssertTrue(no.waitForExistence(timeout: 10), "Keine Frage beim ersten Start")
        XCTAssertTrue(app.buttons["updatePrompt.yes"].exists)
        app.typeKey(.return, modifierFlags: [])
        waitFor(!no.exists, "Frage bleibt nach Return")
        idle(5)
        XCTAssertEqual(server.requests, 0, "Anfrage nach „Nicht suchen“")
        app.terminate()

        launch(try feed() + ["-QuillTestUpdateAsk", "YES"])
        let yes = app.buttons["updatePrompt.yes"]
        XCTAssertTrue(yes.waitForExistence(timeout: 10), "Keine Frage beim ersten Start")
        yes.click()
        waitFor(self.server.requests >= 1, "Keine Anfrage nach „Automatisch suchen“")
        app.typeKey(",", modifierFlags: .command)
        let toggle = app.descendants(matching: .any)["settings.updates.automatic"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? Int, 1, "Antwort nicht übernommen")
    }

    private func feed() throws -> [String] {
        ["-QuillUpdateTestFeed", String(try server.waitForPort())]
    }

    private func launch(_ arguments: [String]) {
        app = XCUIApplication.quill()
        app.launchArguments += arguments
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    private func text(_ element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    private func idle(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Warten")], timeout: seconds)
    }

    private func waitFor(_ condition: @autoclosure @escaping () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 15), .completed, message, file: file, line: line)
    }
}
