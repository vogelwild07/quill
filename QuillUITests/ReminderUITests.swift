import XCTest

/// To-dos mit Erinnerung (15.4, ADR-033). Test-Stores planen nur in einen Ersatz im
/// Speicher, nie Mitteilungen des Macs; was dort ankommt, prüfen die Unit-Tests.
@MainActor
final class ReminderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.quill()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.windows.firstMatch.click()
    }

    override func tearDown() async throws {
        app?.terminate()
    }

    func testRemindMarkRemoveAndCheckOff() throws {
        createPage("Auto")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Werkstatt\r[] Reifen wechseln")

        // Ohne To-do an der Einfügemarke: Hinweis, „Erinnern“ gesperrt.
        app.typeKey(.upArrow, modifierFlags: [])
        openReminderSheet()
        XCTAssertEqual(sheet.staticTexts["reminder.message"].value as? String, "Setze die Einfügemarke in ein offenes To-do.")
        XCTAssertFalse(sheet.buttons["reminder.schedule"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        waitFor(!self.sheet.exists, "Blatt bleibt offen")

        app.typeKey(.downArrow, modifierFlags: [])
        openReminderSheet()
        XCTAssertTrue(sheet.descendants(matching: .any)["reminder.date"].exists)
        sheet.buttons["reminder.schedule"].click()
        waitFor(!self.sheet.exists, "Blatt bleibt nach „Erinnern“ offen")
        XCTAssertTrue(marker.waitForExistence(timeout: 5), "Kein Zeichen am To-do")

        // Zeichen: Zeitpunkt und „Erinnerung entfernen“.
        marker.click()
        let remove = app.buttons["reminder.marker.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "Kein Popover zum Zeichen")
        XCTAssertTrue(app.staticTexts["reminder.marker.date"].exists)
        remove.click()
        waitFor(!self.marker.exists, "Zeichen bleibt nach dem Entfernen")

        // Wieder planen, dann abhaken: Die Erinnerung geht.
        openReminderSheet()
        XCTAssertFalse(sheet.buttons["reminder.remove"].exists, "„Entfernen“ ohne Erinnerung")
        sheet.buttons["reminder.schedule"].click()
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        openReminderSheet()
        XCTAssertTrue(sheet.buttons["reminder.remove"].exists, "„Entfernen“ fehlt bei geplanter Erinnerung")
        app.typeKey(.escape, modifierFlags: [])
        waitFor(!self.sheet.exists, "Blatt bleibt offen")
        app.typeKey(.return, modifierFlags: .command)
        waitFor(!self.marker.exists, "Zeichen bleibt nach dem Abhaken")
    }

    private var editor: XCUIElement {
        app.windows.firstMatch.textViews["editor.text"]
    }

    private var sheet: XCUIElement {
        app.windows.firstMatch.sheets.firstMatch
    }

    private var marker: XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)["editor.marker.reminder"]
    }

    private var outline: XCUIElement {
        app.windows.firstMatch.outlines["sidebar.pages"]
    }

    private func openReminderSheet(file: StaticString = #filePath, line: UInt = #line) {
        app.menuBars.menuBarItems["Format"].click()
        app.menuBars.menuItems["Erinnerung …"].click()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Kein Blatt „Erinnerung“", file: file, line: line)
    }

    /// ⌘N, dann Titel tippen (der Fokus liegt danach im Titelfeld).
    private func createPage(_ name: String) {
        let count = outline.pageRows.count
        app.typeKey("n", modifierFlags: .command)
        waitFor(self.outline.pageRows.count == count + 1, "Keine neue Seite")
        let title = app.windows.firstMatch.descendants(matching: .any)["detail.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        waitForFocus(title)
        app.typeText(name)
    }

    private func waitForFocus(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        waitFor(element.value(forKey: "hasKeyboardFocus") as? Bool == true, "Kein Fokus auf \(element)", file: file, line: line)
    }

    private func waitFor(_ condition: @autoclosure @escaping () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, message, file: file, line: line)
    }
}
