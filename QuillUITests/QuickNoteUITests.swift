import XCTest

/// Schnellnotiz (15.3, ADR-033): Symbol in der Menüleiste, Kürzel ⌃⌥⌘N, Sichern als Seite.
@MainActor
final class QuickNoteUITests: XCTestCase {
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

    func testNoteFromMenuBarAndShortcutBecomesAPage() throws {
        XCTAssertFalse(statusItem.exists, "Standard: aus")
        setSwitches(enabled: true, shortcut: true)

        XCTAssertTrue(statusItem.waitForExistence(timeout: 5), "Kein Symbol in der Menüleiste")
        statusItem.click()
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "Kein Fenster nach Klick auf das Symbol")
        text.typeText("Anruf Werkstatt\nReifen mitnehmen")
        app.typeKey(.return, modifierFlags: .command)
        waitFor(!self.panel.exists, "Fenster bleibt nach dem Sichern offen")
        waitFor(self.pageTitles().contains("Anruf Werkstatt"), "Keine neue Seite in der Sidebar")

        // Kürzel öffnet, Esc schließt, der Entwurf bleibt.
        app.typeKey("n", modifierFlags: [.control, .option, .command])
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "Kein Fenster nach dem Kürzel")
        XCTAssertEqual(text.value as? String, "", "Entwurf nach dem Sichern nicht leer")
        text.typeText("Entwurf")
        app.typeKey(.escape, modifierFlags: [])
        waitFor(!self.panel.exists, "Esc schließt nicht")
        statusItem.click()
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertEqual(text.value as? String, "Entwurf", "Entwurf verloren")
        app.typeKey(.escape, modifierFlags: [])
        waitFor(!self.panel.exists, "Esc schließt nicht")

        setSwitches(enabled: false, shortcut: nil)
        waitFor(!self.statusItem.exists, "Symbol bleibt nach dem Ausschalten")
        app.typeKey("n", modifierFlags: [.control, .option, .command])
        XCTAssertFalse(panel.waitForExistence(timeout: 2), "Kürzel wirkt nach dem Ausschalten")
    }

    private var statusItem: XCUIElement {
        app.statusItems["quicknote.statusItem"]
    }

    private var panel: XCUIElement {
        app.dialogs["quicknote.panel"]
    }

    private var text: XCUIElement {
        panel.textViews["quicknote.text"]
    }

    private func pageTitles() -> [String] {
        app.outlines["sidebar.pages"].pageRows.allElementsBoundByIndex.map { $0.textFields.firstMatch.value as? String ?? "" }
    }

    /// Schaltet in Einstellungen › Schnellnotiz; `nil` lässt den Schalter, wie er ist.
    private func setSwitches(enabled: Bool, shortcut: Bool?) {
        app.typeKey(",", modifierFlags: .command)
        app.toolbars.buttons["Schnellnotiz"].click()
        let main = app.descendants(matching: .any)["settings.quickNote"]
        XCTAssertTrue(main.waitForExistence(timeout: 5))
        if (main.value as? Int == 1) != enabled { main.click() }
        waitFor((main.value as? Int == 1) == enabled, "Schalter Menüleiste nicht umgestellt")
        if let shortcut {
            let key = app.descendants(matching: .any)["settings.quickNoteShortcut"]
            if (key.value as? Int == 1) != shortcut { key.click() }
            waitFor((key.value as? Int == 1) == shortcut, "Schalter Kürzel nicht umgestellt")
            XCTAssertFalse(app.descendants(matching: .any)["settings.quickNoteShortcutTaken"].exists, "Kürzel belegt")
        }
        app.typeKey("w", modifierFlags: .command)
    }

    private func waitFor(_ condition: @autoclosure @escaping () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, message, file: file, line: line)
    }
}
