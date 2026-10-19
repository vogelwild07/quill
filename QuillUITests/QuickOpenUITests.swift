import XCTest

/// „Schnell öffnen“ (⌘O, ADR-017). Daten nur im Arbeitsspeicher (`quill()`).
@MainActor
final class QuickOpenUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.quill()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.windows.firstMatch.click()
    }

    override func tearDown() async throws {
        app.terminate()
    }

    func testFindOpenAndJumpToMatch() throws {
        createPage("Reiseplan")
        createPage("Inbox", text: "Flug für die Reise buchen")
        createPage("Sonstiges")

        // Ohne Begriff: zuletzt bearbeitet. ⎋ schließt.
        app.typeKey("o", modifierFlags: .command)
        waitForFocus(field)
        waitForRows(3)
        app.typeKey(.escape, modifierFlags: [])
        waitForPanel(shown: false)
        XCTAssertEqual(app.windows.firstMatch.title, "Sonstiges")

        // Nach ⇥ bleibt der Fokus im Feld, ⎋ schließt weiterhin.
        app.typeKey("o", modifierFlags: .command)
        waitForFocus(field)
        app.typeKey(.tab, modifierFlags: [])
        waitForFocus(field)
        app.typeKey(.escape, modifierFlags: [])
        waitForPanel(shown: false)

        // Titel vor Inhalt; ↓ ↩ springt zur Fundstelle und wählt sie aus.
        app.typeKey("o", modifierFlags: .command)
        waitForFocus(field)
        app.typeText("reise")
        waitForRowLabels(["Reiseplan", "Inbox, Flug für die Reise buchen"])
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        waitForPanel(shown: false)
        XCTAssertEqual(app.windows.firstMatch.title, "Inbox")
        waitForFocus(editor)
        // Die Auswahl ist genau „Reise“: Tippen ersetzt sie.
        app.typeText("Bahn")
        assertEditorText("Flug für die Bahn buchen\n")

        // ⌘↩ öffnet in neuem Tab.
        app.windows.firstMatch.buttons["sidebar.search"].click()
        waitForFocus(field)
        app.typeText("plan")
        waitForRowLabels(["Reiseplan"])
        app.typeKey(.return, modifierFlags: .command)
        let tabs = NSPredicate { _, _ in self.app.windows.firstMatch.tabGroups.firstMatch.tabs.count == 2 }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: tabs, evaluatedWith: nil)], timeout: 5), .completed, "Kein neuer Tab")
        XCTAssertEqual(app.windows.firstMatch.title, "Reiseplan")

        // Über das Menü öffnen, Klick daneben schließt.
        app.menuBars.menuBarItems["Ablage"].click()
        app.menuBars.menuItems["Schnell öffnen …"].click()
        waitForPanel(shown: true)
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).click()
        waitForPanel(shown: false)
    }

    // MARK: - Hilfen

    private var panel: XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)["quickOpen.panel"]
    }

    private var field: XCUIElement {
        app.windows.firstMatch.textFields["quickOpen.field"]
    }

    private var rows: XCUIElementQuery {
        app.windows.firstMatch.descendants(matching: .any).matching(identifier: "quickOpen.row")
    }

    private var editor: XCUIElement {
        app.windows.firstMatch.textViews["editor.text"]
    }

    private var outline: XCUIElement {
        app.windows.firstMatch.outlines["sidebar.pages"]
    }

    /// ⌘N, Titel tippen, optional ↩ und Text in den ersten Block.
    private func createPage(_ title: String, text: String? = nil) {
        let count = outline.pageRows.count
        app.typeKey("n", modifierFlags: .command)
        let added = NSPredicate { _, _ in self.outline.pageRows.count == count + 1 }
        wait(for: [expectation(for: added, evaluatedWith: nil)], timeout: 5)
        let titleField = app.windows.firstMatch.descendants(matching: .any)["detail.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        waitForFocus(titleField)
        app.typeText(title)
        if let text {
            app.typeText("\r")
            waitForFocus(editor)
            app.typeText(text)
            assertEditorText(text + "\n")
        }
    }

    private func waitForPanel(shown: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let matches = NSPredicate { _, _ in self.panel.exists == shown }
        let result = XCTWaiter.wait(for: [expectation(for: matches, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, shown ? "Schnell öffnen fehlt" : "Schnell öffnen bleibt offen", file: file, line: line)
    }

    private func waitForRows(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let matches = NSPredicate { _, _ in self.rows.count == count }
        let result = XCTWaiter.wait(for: [expectation(for: matches, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, "\(rows.count) statt \(count) Treffer", file: file, line: line)
    }

    private func waitForRowLabels(_ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        let labels = { self.rows.allElementsBoundByIndex.map(\.label) }
        let matches = NSPredicate { _, _ in labels() == expected }
        let result = XCTWaiter.wait(for: [expectation(for: matches, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, "Treffer: \(labels()) statt \(expected)", file: file, line: line)
    }

    private func waitForFocus(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let focused = NSPredicate { _, _ in element.value(forKey: "hasKeyboardFocus") as? Bool == true }
        let result = XCTWaiter.wait(for: [expectation(for: focused, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, "Kein Fokus auf \(element)", file: file, line: line)
    }

    private func assertEditorText(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let matches = NSPredicate { _, _ in self.editor.value as? String == expected }
        let result = XCTWaiter.wait(for: [expectation(for: matches, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, "Editor: \((editor.value as? String)?.debugDescription ?? "nil") statt \(expected.debugDescription)", file: file, line: line)
    }
}
