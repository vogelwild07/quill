import AppKit
import XCTest

/// Block-Editor in der Seite: Tippen, Titel ↔ Text, Formatieren, Speichern beim
/// Seitenwechsel. Daten nur im Arbeitsspeicher (`quill()`); Speichern über einen
/// Neustart ist damit nicht prüfbar und wird von `EditorPersistenceBridgeTests` abgedeckt.
@MainActor
final class EditorUITests: XCTestCase {
    private var app: XCUIApplication!
    /// Eigene Zwischenablage statt der des Nutzers (`-QuillPasteboardName`).
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("de.vogel.quill.uitests.\(UUID().uuidString)"))

    // Die async-Varianten laufen auf dem Main Actor wie die XCUITest-APIs;
    // `setUpWithError`/`tearDownWithError` wären nonisolated.
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.quill()
        app.launchArguments += ["-QuillPasteboardName", pasteboard.name.rawValue]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.windows.firstMatch.click()
    }

    override func tearDown() async throws {
        app.terminate()
        pasteboard.releaseGlobally()
    }

    // MARK: - Tests

    func testTypingBlocksAndMarkdownShortcuts() throws {
        createPage("Notizen")
        app.typeText("\r")
        waitForFocus(editor)

        // ↩ setzt Listen fort, ↩ im leeren Listenpunkt beendet sie.
        app.typeText("# Ziele\r- Punkt\r\r[] Aufgabe\r\rText")
        assertEditorText("Ziele\nPunkt\nAufgabe\nText\n")
    }

    func testTitleAndEditorNavigation() throws {
        createPage("Reise")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Packliste")

        app.typeKey(.upArrow, modifierFlags: [])
        waitForFocus(title)
        app.typeText(" 2027")
        XCTAssertEqual(title.value as? String, "Reise 2027")

        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("x")
        assertEditorText("xPackliste\n")
    }

    func testTextSurvivesPageSwitch() throws {
        createPage("Erste")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Bleibt erhalten\rZweiter Block")

        createPage("Zweite")
        assertEditorText("\n")

        row(0).click()
        assertEditorText("Bleibt erhalten\nZweiter Block\n")
    }

    func testUndoInEditorDoesNotTouchSidebar() throws {
        createPage("Seite")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Hallo")

        app.typeKey("z", modifierFlags: .command)
        assertEditorText("\n")
        XCTAssertEqual(outline.outlineRows.count, 1, "⌘Z im Editor darf keine Seite entfernen")
    }

    func testBoldShortcutAndFormatMenu() throws {
        // Nur der Zähler, nie der Inhalt der Zwischenablage des Nutzers.
        let generalChangeCount = NSPasteboard.general.changeCount
        createPage("Format")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("fett")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("b", modifierFlags: .command)

        app.menuBars.menuBarItems["Format"].click()
        app.menuBars.menuItems["Kursiv"].click()

        app.typeKey("c", modifierFlags: .command)
        let markdown = NSPasteboard.PasteboardType("net.daringfireball.markdown")
        let copied = NSPredicate { _, _ in self.pasteboard.string(forType: markdown) == "**_fett_**" }
        let result = XCTWaiter.wait(for: [expectation(for: copied, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, "Markdown: \(String(describing: pasteboard.string(forType: markdown)))")
        XCTAssertEqual(NSPasteboard.general.changeCount, generalChangeCount, "Allgemeine Zwischenablage wurde verändert")
    }

    func testLinkPopover() throws {
        createPage("Links")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Apple")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("k", modifierFlags: .command)

        let field = app.descendants(matching: .any)["editor.link.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.typeText("apple.com\r")
        XCTAssertFalse(field.waitForExistence(timeout: 1) && field.isHittable, "Popover sollte nach ↩ schließen")
        assertEditorText("Apple\n")
    }

    /// ＋ erscheint bei Hover über einem Block und öffnet darunter das Slash-Menü.
    func testInsertButtonOpensSlashMenu() throws {
        createPage("Einfügen")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Eins")

        // Erster Block direkt unter dem Titel.
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 1)).withOffset(CGVector(dx: 0, dy: 24)).hover()
        let insert = app.windows.firstMatch.buttons["editor.insert"]
        XCTAssertTrue(insert.waitForExistence(timeout: 5), "Kein ＋ bei Hover")
        insert.click()
        assertEditorText("Eins\n/\n")
        XCTAssertTrue(app.descendants(matching: .any)["slash.heading1"].waitForExistence(timeout: 5), "Slash-Menü nicht offen")

        // Escape nimmt den Klick zurück.
        app.typeKey(.escape, modifierFlags: [])
        assertEditorText("Eins\n")

        title.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 1)).withOffset(CGVector(dx: 0, dy: 24)).hover()
        XCTAssertTrue(insert.waitForExistence(timeout: 5))
        insert.click()
        assertEditorText("Eins\n/\n")

        app.typeText("üb\r")
        assertEditorText("Eins\n\n")
        app.typeText("Titel")
        assertEditorText("Eins\nTitel\n")
    }

    /// Slash-Menü über Bedienungshilfen: Tastatur wählt aus, Klick fügt ein.
    func testSlashMenuKeyboardAndMouse() throws {
        createPage("Slash")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("/")
        let menu = app.descendants(matching: .any)["slash.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Slash-Menü nicht erreichbar")
        let heading = menu.descendants(matching: .any)["slash.heading1"]
        XCTAssertTrue(heading.exists)
        app.typeKey(.downArrow, modifierFlags: [])
        let selected = NSPredicate { _, _ in heading.isSelected }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: selected, evaluatedWith: nil)], timeout: 5), .completed, "↓ wählt nicht aus")

        menu.descendants(matching: .any)["slash.divider"].click()
        assertEditorText("\u{FFFC}\n\n")
        XCTAssertFalse(menu.exists)
    }

    /// Klick in die Sidebar schließt das Menü.
    func testSlashMenuClosesWhenFocusLeaves() throws {
        createPage("Fokus")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("/")
        let menu = app.descendants(matching: .any)["slash.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        row(0).click()
        let gone = NSPredicate { _, _ in !menu.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: gone, evaluatedWith: nil)], timeout: 5), .completed, "Menü bleibt offen")
    }

    /// Format › Blockart (⌥⌘0–7) und Abhaken (⌘↩) über die Menüleiste; Ergebnis als
    /// Markdown aus der eigenen Zwischenablage.
    func testBlockKindShortcutsAndCheckOff() throws {
        createPage("Kürzel")
        app.typeText("\r")
        waitForFocus(editor)
        // Zwei Blöcke: dann kopiert ⌘A blockweise mit Markdown-Präfix.
        app.typeText("Titel\rEnde")
        app.typeKey(.upArrow, modifierFlags: .command)

        app.typeKey("1", modifierFlags: [.command, .option])
        XCTAssertEqual(copiedMarkdown(), "# Titel\n\nEnde")
        app.typeKey("6", modifierFlags: [.command, .option])
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertEqual(copiedMarkdown(), "- [x] Titel\n\nEnde")
        app.typeKey("0", modifierFlags: [.command, .option])
        XCTAssertEqual(copiedMarkdown(), "Titel\n\nEnde")

        let blockKinds = app.menuBars.menuBarItems["Format"].menuItems["Blockart"]
        app.menuBars.menuBarItems["Format"].click()
        XCTAssertTrue(blockKinds.waitForExistence(timeout: 5))
        blockKinds.hover()
        XCTAssertTrue(blockKinds.menuItems["Code"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
    }

    /// ⌥⌘↓ verschiebt, Kontextmenü am Griff dupliziert, ⌘D dupliziert die Auswahl.
    func testMoveAndDuplicateBlocks() throws {
        createPage("Blöcke")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Eins\rZwei")
        app.typeKey(.upArrow, modifierFlags: .command)
        app.typeKey(.downArrow, modifierFlags: [.command, .option])
        assertEditorText("Zwei\nEins\n")

        title.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 1)).withOffset(CGVector(dx: 0, dy: 24)).hover()
        let handle = app.windows.firstMatch.handles.firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5), "Kein Griff bei Hover")
        handle.rightClick()
        let duplicate = app.menuItems["Duplizieren"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5), "Kein Kontextmenü am Griff")
        XCTAssertTrue(app.menuItems["Umwandeln in"].exists)
        duplicate.click()
        assertEditorText("Zwei\nZwei\nEins\n")

        app.typeKey("d", modifierFlags: .command)
        assertEditorText("Zwei\nZwei\nZwei\nEins\n")
        app.typeKey("z", modifierFlags: .command)
        assertEditorText("Zwei\nZwei\nEins\n")
    }

    // MARK: - Hilfen

    /// ⌘A, ⌘C im Editor; liest Markdown aus der eigenen Zwischenablage. Danach steht
    /// der Cursor wieder am Anfang.
    private func copiedMarkdown() -> String? {
        app.typeKey("a", modifierFlags: .command)
        let before = pasteboard.changeCount
        app.typeKey("c", modifierFlags: .command)
        let copied = NSPredicate { _, _ in self.pasteboard.changeCount != before }
        _ = XCTWaiter.wait(for: [expectation(for: copied, evaluatedWith: nil)], timeout: 5)
        app.typeKey(.upArrow, modifierFlags: .command)
        return pasteboard.string(forType: NSPasteboard.PasteboardType("net.daringfireball.markdown"))
    }

    private var outline: XCUIElement {
        app.windows.firstMatch.outlines["sidebar.pages"]
    }

    private var editor: XCUIElement {
        app.windows.firstMatch.textViews["editor.text"]
    }

    private var title: XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)["detail.title"]
    }

    private func row(_ index: Int) -> XCUIElement {
        outline.outlineRows.element(boundBy: index)
    }

    /// ⌘N, dann Titel tippen (der Fokus liegt danach im Titelfeld).
    private func createPage(_ name: String) {
        let count = outline.outlineRows.count
        app.typeKey("n", modifierFlags: .command)
        let added = NSPredicate { _, _ in self.outline.outlineRows.count == count + 1 }
        wait(for: [expectation(for: added, evaluatedWith: nil)], timeout: 5)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        waitForFocus(title)
        app.typeText(name)
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
