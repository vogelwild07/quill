import XCTest

/// Zeitreise (12.3, ADR-031): Fenster per ⌥⌘Y, Tage links, früherer Stand
/// schreibgeschützt, markierte Absätze zurückholen. Die Geschichte über drei Tage legt
/// die App selbst an (`-QuillSeedTimeTravel`, nur Debug und Test-Store).
@MainActor
final class TimeTravelUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.quill()
        app.launchArguments += ["-QuillSeedTimeTravel", "YES"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.windows.firstMatch.click()
    }

    override func tearDown() async throws {
        app.terminate()
    }

    func testOpenEarlierDayAndRestoreParagraph() throws {
        let main = app.windows.firstMatch
        let row = main.outlines["sidebar.pages"].pageRows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Testseite fehlt")
        row.click()
        let editor = main.textViews["editor.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse(editorText(editor).contains("Alter Absatz"))

        app.typeKey("y", modifierFlags: [.command, .option])
        let window = app.windows["Zeitreise: Zeitreise-Test"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Fenster „Zeitreise“ fehlt")
        let days = window.descendants(matching: .any).matching(identifier: "timeTravel.day")
        XCTAssertTrue(days.element(boundBy: 2).waitForExistence(timeout: 10), "Drei Tage erwartet")
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(text(of: days.element(boundBy: 0)), "Heute")
        XCTAssertEqual(text(of: days.element(boundBy: 1)), "Gestern")

        let restore = window.buttons["timeTravel.restore"]
        days.element(boundBy: 2).click()
        let old = window.textViews["editor.text"]
        XCTAssertTrue(old.waitForExistence(timeout: 5))
        waitFor(self.editorText(old).contains("Alter Absatz"), "Vorgestern fehlt „Alter Absatz“")
        XCTAssertFalse(restore.isEnabled, "Ohne Markierung nichts zurückzuholen")

        // Schreibgeschützt: Tippen ändert den früheren Stand nicht.
        old.click()
        app.typeText("x")
        XCTAssertFalse(editorText(old).contains("x"))

        // Nur den zweiten Absatz per Tastatur markieren (Lesemodus mit Schreibmarke).
        app.typeKey(.upArrow, modifierFlags: [.command])
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: [.command, .shift])
        waitFor(restore.isEnabled, "Mit Markierung soll „Auswahl zurückholen“ gehen")
        restore.click()

        // Im Editor der Seite steht der Absatz wieder, hinter „Erster Absatz“.
        waitFor(self.editorText(editor).contains("Erster Absatz\nAlter Absatz"), "„Alter Absatz“ nicht zurück: \(editorText(editor))")
        // „Heute“ zeigt jetzt den zurückgeholten Stand.
        days.element(boundBy: 0).click()
        waitFor(self.editorText(old).contains("Alter Absatz"), "„Heute“ ohne Rückholung")
    }

    // MARK: - Hilfen

    /// Text einer Zeile: unter macOS im Wert, nicht in der Beschriftung.
    private func text(of element: XCUIElement) -> String {
        element.value as? String ?? element.label
    }

    private func editorText(_ element: XCUIElement) -> String {
        element.value as? String ?? ""
    }

    private func waitFor(_ condition: @autoclosure @escaping () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, message, file: file, line: line)
    }
}
