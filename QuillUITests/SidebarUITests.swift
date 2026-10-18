import XCTest

/// Seitenbaum, Menüleiste und Tabs. Daten nur im Arbeitsspeicher (`quill()`).
@MainActor
final class SidebarUITests: XCTestCase {
    private var app: XCUIApplication!

    // Die async-Varianten laufen auf dem Main Actor wie die XCUITest-APIs;
    // `setUpWithError`/`tearDownWithError` wären nonisolated.
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.quill()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.windows.firstMatch.click()
    }

    // MARK: - Tests

    func testCreateAndRenamePage() throws {
        createPage("Inbox")
        assertTitles(["Inbox"])

        row(0).click()
        app.typeKey(.return, modifierFlags: [])
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Eingang\r")

        assertTitles(["Eingang"])
        XCTAssertEqual(app.windows.firstMatch.title, "Eingang")
    }

    func testSubpageTrashAndUndo() throws {
        createPage("Projekte")
        createPage("Quill", subpage: true)
        assertTitles(["Projekte", "Quill"])
        XCTAssertTrue(row(0).disclosureTriangles.firstMatch.exists, "Projekte sollte ausklappbar sein")

        row(0).click()
        app.typeKey(.delete, modifierFlags: .command)
        assertTitles([])

        app.typeKey("z", modifierFlags: .command)
        assertTitles(["Projekte", "Quill"])
    }

    /// Übersprungen: Synthetische Drags von XCUITest (`press(forDuration:thenDragTo:)`,
    /// auch langsam und per Koordinate auf dem Icon) starten in der `NSOutlineView`
    /// kein Ziehen; von Hand funktioniert es (geprüft 2026-10-18). Abgedeckt durch
    /// `PageTreeTests` (Drop-Position, Zyklen) und `PageStoreTests` (Verschieben, Undo-Ort).
    func testDragOntoPageNestsIt() throws {
        try XCTSkipIf(true, "XCUITest-Drags erreichen die NSOutlineView nicht, siehe Kommentar.")
        createPage("Ziel")
        createPage("Gezogen")
        assertTitles(["Ziel", "Gezogen"])
        XCTAssertFalse(row(0).disclosureTriangles.firstMatch.exists)

        row(1).press(forDuration: 0.5, thenDragTo: row(0), withVelocity: .slow, thenHoldForDuration: 0.5)

        let nested = NSPredicate { _, _ in self.row(0).disclosureTriangles.firstMatch.exists }
        wait(for: [expectation(for: nested, evaluatedWith: nil)], timeout: 5)
        assertTitles(["Ziel", "Gezogen"])

        app.typeKey("z", modifierFlags: .command)
        let flat = NSPredicate { _, _ in !self.row(0).disclosureTriangles.firstMatch.exists }
        wait(for: [expectation(for: flat, evaluatedWith: nil)], timeout: 5)
    }

    func testNewTabAndOpenPageInTab() throws {
        createPage("Reise")
        app.typeKey("t", modifierFlags: .command)
        waitForTabCount(2)

        // Im neuen Tab die Seite auswählen und über das Menü in einem weiteren Tab öffnen.
        row(0).click()
        app.menuBars.menuBarItems["Seite"].click()
        app.menuBars.menuItems["In neuem Tab öffnen"].click()

        waitForTabCount(3)
        XCTAssertEqual(app.windows.firstMatch.title, "Reise")
    }

    // MARK: - Hilfen

    private var outline: XCUIElement {
        app.windows.firstMatch.outlines["sidebar.pages"]
    }

    private func row(_ index: Int) -> XCUIElement {
        outline.outlineRows.element(boundBy: index)
    }

    private func titles() -> [String] {
        outline.outlineRows.allElementsBoundByIndex.map { row in
            row.textFields.firstMatch.value as? String ?? ""
        }
    }

    /// ⌘N bzw. ⇧⌘N, dann Titel tippen (der Fokus liegt danach im Titelfeld).
    private func createPage(_ title: String, subpage: Bool = false) {
        let count = outline.outlineRows.count
        app.typeKey("n", modifierFlags: subpage ? [.command, .shift] : .command)
        let added = NSPredicate { _, _ in self.outline.outlineRows.count == count + 1 }
        wait(for: [expectation(for: added, evaluatedWith: nil)], timeout: 5)

        let field = app.windows.firstMatch.descendants(matching: .any)["detail.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let focused = NSPredicate { _, _ in field.value(forKey: "hasKeyboardFocus") as? Bool == true }
        wait(for: [expectation(for: focused, evaluatedWith: nil)], timeout: 5)
        app.typeText(title)
        let shown = NSPredicate { _, _ in self.titles().contains(title) }
        wait(for: [expectation(for: shown, evaluatedWith: nil)], timeout: 5)
    }

    private func assertTitles(_ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        let matches = NSPredicate { _, _ in self.titles() == expected }
        let result = XCTWaiter.wait(for: [expectation(for: matches, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, "Sidebar: \(titles()) statt \(expected)", file: file, line: line)
    }

    private func waitForTabCount(_ count: Int) {
        let tabs = NSPredicate { _, _ in
            self.app.windows.firstMatch.tabGroups.firstMatch.tabs.count == count
        }
        wait(for: [expectation(for: tabs, evaluatedWith: nil)], timeout: 5)
    }
}
