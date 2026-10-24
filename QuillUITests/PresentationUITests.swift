import XCTest

/// Präsentieren (18.2, ADR-035). Test-Stores zeigen die Präsentation im Fenster statt im
/// Vollbild.
@MainActor
final class PresentationUITests: XCTestCase {
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

    func testSlidesAtHeadingsAndEscape() throws {
        createPage("Vortrag")
        app.typeText("\r")
        waitForFocus(editor)
        // Direkt danach präsentieren: Die Präsentation speichert offene Änderungen selbst.
        app.typeText("Einleitung\r# Eins\r# Zwei")
        waitFor(self.editorText == "Einleitung\nEins\nZwei\n", "Seite nicht getippt: \(editorText)")
        app.typeKey("p", modifierFlags: [.command, .option])

        XCTAssertTrue(presentation.waitForExistence(timeout: 5), "Kein Fenster „Präsentation“")
        waitFor(self.counter == "Folie 1 von 3", "Falscher Zähler: \(counter)")
        waitFor(self.slideText == "Vortrag\nEinleitung\n", "Erste Folie: \(slideText)")

        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(" ", modifierFlags: [])
        waitFor(self.counter == "Folie 3 von 3", "Falscher Zähler: \(counter)")
        XCTAssertEqual(slideText, "Zwei\n")
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertEqual(counter, "Folie 3 von 3", "Läuft über die letzte Folie hinaus")

        app.typeKey(.leftArrow, modifierFlags: [])
        waitFor(self.slideText == "Eins\n", "Zurück: \(slideText)")
        app.typeKey(.home, modifierFlags: [])
        waitFor(self.counter == "Folie 1 von 3", "Pos1: \(counter)")

        app.typeKey(.escape, modifierFlags: [])
        waitFor(!self.presentation.exists, "Esc schließt die Präsentation nicht")
        XCTAssertEqual(editorText, "Einleitung\nEins\nZwei\n", "Seite verändert")
    }

    private var presentation: XCUIElement {
        app.windows.matching(NSPredicate(format: "title BEGINSWITH %@", "Präsentation")).firstMatch
    }

    private var counter: String {
        presentation.staticTexts["presentation.counter"].value as? String ?? ""
    }

    private var slideText: String {
        presentation.textViews["editor.text"].value as? String ?? ""
    }

    private var editor: XCUIElement {
        app.windows.matching(NSPredicate(format: "NOT (title BEGINSWITH %@)", "Präsentation")).firstMatch.textViews["editor.text"]
    }

    private var editorText: String {
        editor.value as? String ?? ""
    }

    private var outline: XCUIElement {
        app.windows.firstMatch.outlines["sidebar.pages"]
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

    private func waitFor(_ condition: @autoclosure @escaping () -> Bool, _ message: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, message(), file: file, line: line)
    }
}
