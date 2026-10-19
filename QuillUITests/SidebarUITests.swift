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

    /// Auswahl in der Sidebar und angezeigte Seite bleiben gleich: beim Anlegen,
    /// Anklicken, Umbenennen, Papierkorb (Auswahl geht an die Elternseite), Undo und
    /// „Schnell öffnen“ (Phase 7.2, Sidebar baut ihren Baum nur bei geänderten Seiten).
    func testSelectionStaysInSync() throws {
        createPage("Eltern")
        createPage("Kind", subpage: true)
        createPage("Andere")
        assertTitles(["Eltern", "Kind", "Andere"])
        assertSelected("Andere")

        row(1).click()
        assertSelected("Kind")

        app.typeKey(.return, modifierFlags: [])
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Kind neu\r")
        assertTitles(["Eltern", "Kind neu", "Andere"])
        assertSelected("Kind neu")

        app.typeKey(.delete, modifierFlags: .command)
        assertTitles(["Eltern", "Andere"])
        assertSelected("Eltern")

        app.typeKey("z", modifierFlags: .command)
        assertTitles(["Eltern", "Kind neu", "Andere"])
        assertSelected("Eltern")

        app.typeKey("o", modifierFlags: .command)
        app.typeText("Andere")
        let hit = app.windows.firstMatch.descendants(matching: .any).matching(identifier: "quickOpen.row").firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        assertSelected("Andere")
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

    /// Papierkorb (ADR-017): Wiederherstellen, endgültig löschen mit Rückfrage, leeren.
    func testTrashRestoreDeleteAndEmpty() throws {
        createPage("Eins")
        createPage("Zwei")
        assertTitles(["Eins", "Zwei"])
        for _ in 0..<2 {
            row(0).click()
            app.typeKey(.delete, modifierFlags: .command)
        }
        assertTitles([])

        app.windows.firstMatch.buttons["sidebar.trash"].click()
        waitForTrashRows(2)
        // Symbol wie in der Sidebar statt Emoji; Doppelklick stellt nicht wieder her.
        XCTAssertFalse(trashRowLabel(0).contains("📄"), trashRowLabel(0))
        trashRows.element(boundBy: 0).doubleClick()
        sleep(1)
        waitForTrashRows(2)
        assertTitles([])

        // Wiederherstellen: Seite ist wieder in der Sidebar.
        trashRows.element(boundBy: 0).click()
        app.windows.firstMatch.buttons["trash.restore"].click()
        waitForTrashRows(1)
        assertTitles(["Zwei"])
        // Undo legt sie zurück in den Papierkorb.
        app.typeKey("z", modifierFlags: .command)
        waitForTrashRows(2)
        assertTitles([])
        trashRows.element(boundBy: 0).click()
        app.windows.firstMatch.buttons["trash.restore"].click()
        waitForTrashRows(1)
        assertTitles(["Zwei"])

        // ⌫ fragt nach; Abbrechen lässt die Seite liegen, Bestätigen löscht sie.
        trashRows.element(boundBy: 0).click()
        app.typeKey(.delete, modifierFlags: [])
        answerConfirmation(confirm: false)
        waitForTrashRows(1)
        app.typeKey(.delete, modifierFlags: [])
        answerConfirmation(confirm: true)
        waitForTrashRows(0)

        // Leeren.
        row(0).click()
        app.typeKey(.delete, modifierFlags: .command)
        app.windows.firstMatch.buttons["sidebar.trash"].click()
        waitForTrashRows(1)
        app.windows.firstMatch.buttons["trash.empty"].click()
        answerConfirmation(confirm: true)
        waitForTrashRows(0)
        XCTAssertFalse(app.windows.firstMatch.buttons["trash.empty"].isEnabled)
        assertTitles([])
    }

    /// Favoriten (ADR-017): Stern, Menü „Seite“, Kontextmenü, Undo und Papierkorb.
    func testFavorites() throws {
        createPage("Eins")
        createPage("Zwei")
        assertTitles(["Eins", "Zwei"])
        assertFavorites([])
        XCTAssertEqual(groupTitles(), ["Seiten"], "Ohne Favoriten kein Abschnitt")

        // Stern in der Symbolleiste.
        let star = app.windows.firstMatch.buttons["page.favorite"]
        row(1).click()
        XCTAssertEqual(star.label, "Zu Favoriten hinzufügen", "Stern leer, solange kein Favorit")
        star.click()
        assertFavorites(["Zwei"])
        XCTAssertEqual(groupTitles(), ["Favoriten", "Seiten"])
        XCTAssertEqual(star.label, "Aus Favoriten entfernen", "Stern gefüllt nach dem Hinzufügen")

        // Menü „Seite“.
        row(0).click()
        XCTAssertEqual(star.label, "Zu Favoriten hinzufügen", "Stern folgt der Auswahl")
        app.menuBars.menuBarItems["Seite"].click()
        app.menuBars.menuItems["Zu Favoriten hinzufügen"].click()
        assertFavorites(["Zwei", "Eins"])

        // Kontextmenü am ersten Favoriten; ⌘Z holt ihn an seinen Platz zurück,
        // ein weiteres ⌘Z nimmt das Hinzufügen von „Eins“ zurück.
        outline.favoriteRows.element(boundBy: 0).rightClick()
        outline.menuItems["Aus Favoriten entfernen"].click()
        assertFavorites(["Eins"])
        app.typeKey("z", modifierFlags: .command)
        assertFavorites(["Zwei", "Eins"])
        app.typeKey("z", modifierFlags: .command)
        assertFavorites(["Zwei"])

        // Klick auf den Favoriten öffnet die Seite.
        outline.favoriteRows.element(boundBy: 0).click()
        XCTAssertEqual(app.windows.firstMatch.title, "Zwei")

        // Im Papierkorb verschwindet der Favorit, wiederhergestellt ist er zurück.
        row(1).click()
        app.typeKey(.delete, modifierFlags: .command)
        assertTitles(["Eins"])
        assertFavorites([])
        app.typeKey("z", modifierFlags: .command)
        assertTitles(["Eins", "Zwei"])
        assertFavorites(["Zwei"])
    }

    // MARK: - Hilfen

    private func favoriteTitles() -> [String] {
        outline.favoriteRows.allElementsBoundByIndex.map { $0.textFields.firstMatch.value as? String ?? "" }
    }

    private func groupTitles() -> [String] {
        outline.staticTexts.matching(identifier: "sidebar.group").allElementsBoundByIndex.map { $0.value as? String ?? "" }
    }

    private func assertFavorites(_ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        let matches = NSPredicate { _, _ in self.favoriteTitles() == expected }
        let result = XCTWaiter.wait(for: [expectation(for: matches, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, "Favoriten: \(favoriteTitles()) statt \(expected)", file: file, line: line)
    }

    private var trashRows: XCUIElementQuery {
        app.windows.firstMatch.descendants(matching: .any).matching(identifier: "trash.row")
    }

    private func trashRowLabel(_ index: Int) -> String {
        let row = trashRows.element(boundBy: index)
        return (row.value as? String) ?? row.label
    }

    private func waitForTrashRows(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let matches = NSPredicate { _, _ in self.trashRows.count == count }
        let result = XCTWaiter.wait(for: [expectation(for: matches, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, "Papierkorb: \(trashRows.count) statt \(count) Einträge", file: file, line: line)
    }

    /// Rückfrage beantworten. Das Fenster meldet sich in AX schon vorher als
    /// gesperrt, deshalb auf das Sheet selbst warten und danach auf sein Verschwinden.
    private func answerConfirmation(confirm: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let sheet = app.windows.firstMatch.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Keine Rückfrage", file: file, line: line)
        sheet.buttons[confirm ? "action-button-1" : "action-button-2"].click()
        let gone = NSPredicate { _, _ in !sheet.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: gone, evaluatedWith: nil)], timeout: 5), .completed, "Rückfrage bleibt offen", file: file, line: line)
    }

    private var outline: XCUIElement {
        app.windows.firstMatch.outlines["sidebar.pages"]
    }

    private func row(_ index: Int) -> XCUIElement {
        outline.pageRows.element(boundBy: index)
    }

    private func titles() -> [String] {
        outline.pageRows.allElementsBoundByIndex.map { row in
            row.textFields.firstMatch.value as? String ?? ""
        }
    }

    /// ⌘N bzw. ⇧⌘N, dann Titel tippen (der Fokus liegt danach im Titelfeld).
    private func createPage(_ title: String, subpage: Bool = false) {
        let count = outline.pageRows.count
        app.typeKey("n", modifierFlags: subpage ? [.command, .shift] : .command)
        let added = NSPredicate { _, _ in self.outline.pageRows.count == count + 1 }
        wait(for: [expectation(for: added, evaluatedWith: nil)], timeout: 5)

        let field = app.windows.firstMatch.descendants(matching: .any)["detail.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let focused = NSPredicate { _, _ in field.value(forKey: "hasKeyboardFocus") as? Bool == true }
        wait(for: [expectation(for: focused, evaluatedWith: nil)], timeout: 5)
        app.typeText(title)
        let shown = NSPredicate { _, _ in self.titles().contains(title) }
        wait(for: [expectation(for: shown, evaluatedWith: nil)], timeout: 5)
    }

    /// Fenstertitel und ausgewählte Zeile der Sidebar zeigen dieselbe Seite.
    private func assertSelected(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        func selected() -> [String] {
            outline.pageRows.allElementsBoundByIndex.filter(\.isSelected).map { $0.textFields.firstMatch.value as? String ?? "" }
        }
        let matches = NSPredicate { _, _ in self.app.windows.firstMatch.title == title && selected() == [title] }
        let result = XCTWaiter.wait(for: [expectation(for: matches, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(
            result, .completed,
            "Fenster „\(app.windows.firstMatch.title)“, Auswahl \(selected()) statt „\(title)“", file: file, line: line
        )
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
