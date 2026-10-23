import XCTest

/// Tagesseite mit heutigen Terminen (15.5, ADR-033). Test-Stores lesen nie den Kalender
/// des Macs, sondern zwei feste Termine im Speicher („Zahnarzt“ 9–10 Uhr, „Geburtstag“
/// ganztägig).
@MainActor
final class TodayUITests: XCTestCase {
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

    func testOpenTodayAndInsertEvents() throws {
        let day = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        app.typeKey("t", modifierFlags: [.command, .shift])
        waitFor(self.window.title == day, "Tagesseite nicht geöffnet")
        let days = outline.pageRows.containing(NSPredicate(format: "value == %@", "Tage")).firstMatch
        XCTAssertTrue(days.waitForExistence(timeout: 5), "Keine Sammelseite „Tage“")
        let count = outline.pageRows.count

        // Ohne Einfügemarke im Editor: Hinweis statt Termine.
        title.click()
        waitForFocus(title)
        insertEvents()
        let notice = window.sheets.firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "Kein Hinweis ohne Einfügemarke")
        XCTAssertTrue(notice.staticTexts["Setze die Einfügemarke in eine Seite."].exists)
        notice.buttons.firstMatch.click()
        waitFor(!notice.exists, "Hinweis bleibt offen")

        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Plan")
        insertEvents()
        waitFor(self.editorText.contains("Zahnarzt"), "Termine nicht eingefügt")
        XCTAssertTrue(editorText.hasPrefix("Plan\nGanztägig: Geburtstag\n"), editorText)
        XCTAssertTrue(editorText.contains("–10:00 Zahnarzt"), editorText)

        app.typeKey("z", modifierFlags: .command)
        waitFor(!self.editorText.contains("Zahnarzt"), "⌘Z nimmt die Termine nicht zurück")
        XCTAssertTrue(editorText.hasPrefix("Plan"))

        // Von „Tage“ aus noch einmal „Heute“: dieselbe Seite, keine neue.
        days.click()
        waitFor(self.window.title == "Tage", "„Tage“ nicht ausgewählt")
        app.typeKey("t", modifierFlags: [.command, .shift])
        waitFor(self.window.title == day, "Tagesseite nicht wieder geöffnet")
        XCTAssertEqual(outline.pageRows.count, count)
        XCTAssertTrue(editorText.hasPrefix("Plan"), "Andere Tagesseite geöffnet")
    }

    private var window: XCUIElement {
        app.windows.firstMatch
    }

    private var editor: XCUIElement {
        window.textViews["editor.text"]
    }

    private var editorText: String {
        editor.value as? String ?? ""
    }

    private var title: XCUIElement {
        window.descendants(matching: .any)["detail.title"]
    }

    private var outline: XCUIElement {
        window.outlines["sidebar.pages"]
    }

    private func insertEvents() {
        app.menuBars.menuBarItems["Format"].click()
        app.menuBars.menuItems["Heutige Termine einfügen"].click()
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
