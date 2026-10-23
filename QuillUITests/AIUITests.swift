import AppKit
import XCTest

/// Lokale KI (ADR-032): Einstellungen › KI (16.1), Seite zusammenfassen (16.2), To-dos
/// vorschlagen (16.3), Frag deine Notizen (16.4), verwandte Seiten (16.5). Statt Apple Intelligence ein Test-Modell (`-QuillFakeAI`, nur Debug
/// und Test-Store), damit der Test auf jedem Mac gleich läuft; es antwortet mit der ersten
/// Zeile der Anfrage, Listen mit einem Eintrag je Zeile.
@MainActor
final class AIUITests: XCTestCase {
    private var app: XCUIApplication!
    /// Eigene Zwischenablage statt der des Nutzers (`-QuillPasteboardName`).
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.vogelwild07.quill.uitests.\(UUID().uuidString)"))

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        app?.terminate()
        pasteboard.releaseGlobally()
    }

    private func launch(availability: String) {
        app = XCUIApplication.quill()
        app.launchArguments += ["-QuillFakeAI", availability, "-QuillPasteboardName", pasteboard.name.rawValue]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.windows.firstMatch.click()
    }

    private func openAISettings() {
        app.typeKey(",", modifierFlags: .command)
        app.toolbars.buttons["KI"].click()
    }

    // MARK: - Einstellungen

    func testTurnOffAI() throws {
        launch(availability: "available")
        openAISettings()
        let toggle = app.descendants(matching: .any)["settings.aiEnabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertEqual(toggle.value as? Int, 1, "Standard: an")
        XCTAssertFalse(app.descendants(matching: .any)["settings.aiUnavailable"].exists)
        toggle.click()
        waitFor((toggle.value as? Int) == 0, "KI nicht ausgeschaltet")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertFalse(summarizeMenuItem.exists, "„Zusammenfassen …“ trotz ausgeschalteter KI")
        XCTAssertFalse(app.menuBars.menuItems["To-dos vorschlagen …"].exists, "„To-dos vorschlagen …“ trotz ausgeschalteter KI")
        XCTAssertFalse(app.menuBars.menuItems["Verwandte Seiten …"].exists, "„Verwandte Seiten …“ trotz ausgeschalteter KI")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(askMenuItem.exists, "„Frag deine Notizen …“ trotz ausgeschalteter KI")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testExplainsMissingAppleIntelligence() throws {
        launch(availability: "appleIntelligenceNotEnabled")
        openAISettings()
        let reason = app.descendants(matching: .any)["settings.aiUnavailable"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        let text = reason.label + (reason.value as? String ?? "")
        XCTAssertTrue(text.contains("Apple Intelligence ist aus"), text)
        XCTAssertFalse(app.descendants(matching: .any)["settings.aiEnabled"].exists, "Ohne Modell kein Schalter")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertFalse(summarizeMenuItem.exists, "„Zusammenfassen …“ ohne Modell")
        XCTAssertFalse(app.menuBars.menuItems["To-dos vorschlagen …"].exists, "„To-dos vorschlagen …“ ohne Modell")
        XCTAssertFalse(app.menuBars.menuItems["Verwandte Seiten …"].exists, "„Verwandte Seiten …“ ohne Modell")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(askMenuItem.exists, "„Frag deine Notizen …“ ohne Modell")
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Zusammenfassen

    func testSummarizeAndInsertAtCursor() throws {
        launch(availability: "available")
        createPage("Ausflug")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Wir fahren an den See.\rDann essen wir.\r")

        XCTAssertTrue(summarizeMenuItem.waitForExistence(timeout: 5))
        summarizeMenuItem.click()
        let summary = app.descendants(matching: .any)["summary.text"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        let insert = app.buttons["summary.insert"]
        XCTAssertTrue(insert.isEnabled)
        insert.click()
        assertEditorText("Wir fahren an den See.\nDann essen wir.\nAntwort des Test-Modells: Wir fahren an den See.\n")

        app.typeKey("z", modifierFlags: .command)
        assertEditorText("Wir fahren an den See.\nDann essen wir.\n\n")
    }

    func testSummaryOfAnEmptyPageExplainsWhy() throws {
        launch(availability: "available")
        createPage("Leer")
        summarizeMenuItem.click()
        let problem = app.descendants(matching: .any)["summary.problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["summary.insert"].exists, "Einfügen nur, wenn der Editor den Fokus hatte")
        app.typeKey(.escape, modifierFlags: [])
        waitFor(!problem.exists, "Blatt nicht geschlossen")
    }

    // MARK: - To-dos

    func testSuggestTodosAndInsertBelowSelection() throws {
        launch(availability: "available")
        createPage("Woche")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Milch kaufen\rOma anrufen")
        app.typeKey("a", modifierFlags: .command)

        todosMenuItem.click()
        XCTAssertTrue(app.descendants(matching: .any)["todos.list"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["To-do: Oma anrufen"].exists)
        app.buttons["todos.insert"].click()
        assertEditorText("Milch kaufen\nOma anrufen\nTo-do: Milch kaufen\nTo-do: Oma anrufen\n")

        app.typeKey("z", modifierFlags: .command)
        assertEditorText("Milch kaufen\nOma anrufen\n")
    }

    func testSuggestTodosNeedsMarkedParagraphs() throws {
        launch(availability: "available")
        createPage("Woche")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Milch kaufen")

        todosMenuItem.click()
        let problem = app.descendants(matching: .any)["todos.problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 10))
        let text = problem.label + (problem.value as? String ?? "")
        XCTAssertTrue(text.contains("Markiere zuerst"), text)
        XCTAssertFalse(app.buttons["todos.insert"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        waitFor(!problem.exists, "Blatt nicht geschlossen")
    }

    // MARK: - Frag deine Notizen

    func testAskNotesAnswersAndOpensTheSource() throws {
        launch(availability: "available")
        createPage("Einkauf")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Milch kaufen")
        createPage("Urlaub")

        askMenuItem.click()
        let question = app.descendants(matching: .any)["ask.question"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        waitForFocus(question)
        app.typeText("Was soll ich kaufen?\r")
        let answer = app.descendants(matching: .any)["ask.answer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        let text = answer.label + (answer.value as? String ?? "")
        XCTAssertTrue(text.contains("Antwort des Test-Modells: Frage: Was soll ich kaufen?"), text)
        // Als Link gestaltet: nicht unbedingt ein Button für die Bedienungshilfen.
        let sources = app.descendants(matching: .any).matching(identifier: "ask.source")
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.firstMatch.label, "Einkauf")

        sources.firstMatch.click()
        waitFor(!question.exists, "Blatt nicht geschlossen")
        waitFor((self.title.value as? String) == "Einkauf", "Quelle nicht geöffnet")
    }

    func testAskNotesWithoutMatchingPageExplains() throws {
        launch(availability: "available")
        createPage("Einkauf")
        askMenuItem.click()
        let question = app.descendants(matching: .any)["ask.question"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ask.submit"].isEnabled, "Fragen ohne Frage")
        waitForFocus(question)
        app.typeText("Xylophon?\r")
        let problem = app.descendants(matching: .any)["ask.problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 10))
        let text = problem.label + (problem.value as? String ?? "")
        XCTAssertTrue(text.contains("keine passenden Seiten"), text)
        app.typeKey(.escape, modifierFlags: [])
        waitFor(!problem.exists, "Blatt nicht geschlossen")
    }

    // MARK: - Verwandte Seiten

    func testRelatedPagesShowSharedTermsAndOpenThePage() throws {
        launch(availability: "available")
        // Das Test-Modell macht aus jeder Zeile „To-do: <Zeile>“; die Suche findet das wörtlich.
        createPage("Liste")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("To-do: Milch kaufen und Brot")
        createPage("Urlaub")
        createPage("Einkauf")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Milch kaufen")

        relatedMenuItem.click()
        let pages = app.descendants(matching: .any).matching(identifier: "related.page")
        XCTAssertTrue(pages.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages.firstMatch.label, "Liste")
        let terms = app.descendants(matching: .any)["related.terms"]
        let text = terms.label + (terms.value as? String ?? "")
        XCTAssertTrue(text.contains("Gemeinsam: To-do: Milch kaufen"), text)

        pages.firstMatch.click()
        waitFor(!terms.exists, "Blatt nicht geschlossen")
        waitFor((self.title.value as? String) == "Liste", "Seite nicht geöffnet")
    }

    func testRelatedPagesWithoutMatchSayNone() throws {
        launch(availability: "available")
        createPage("Einkauf")
        createPage("Kuchen")
        relatedMenuItem.click()
        let empty = app.descendants(matching: .any)["related.emptyState.title"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["related.page"].exists)
        app.typeKey(.escape, modifierFlags: [])
        waitFor(!empty.exists, "Blatt nicht geschlossen")
    }

    // MARK: - Hilfen

    /// Öffnet das Menü „Ablage“ und gibt den Eintrag zurück (ohne zu klicken).
    private var askMenuItem: XCUIElement {
        app.typeKey(.escape, modifierFlags: [])
        app.menuBars.menuBarItems["Ablage"].click()
        return app.menuBars.menuItems["Frag deine Notizen …"]
    }

    private var todosMenuItem: XCUIElement {
        app.menuBars.menuBarItems["Seite"].click()
        return app.menuBars.menuItems["To-dos vorschlagen …"]
    }

    private var relatedMenuItem: XCUIElement {
        app.menuBars.menuBarItems["Seite"].click()
        return app.menuBars.menuItems["Verwandte Seiten …"]
    }

    /// Öffnet das Menü „Seite“ und gibt den Eintrag zurück (ohne zu klicken).
    private var summarizeMenuItem: XCUIElement {
        app.menuBars.menuBarItems["Seite"].click()
        return app.menuBars.menuItems["Zusammenfassen …"]
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

    /// ⌘N, dann Titel tippen (der Fokus liegt danach im Titelfeld).
    private func createPage(_ name: String) {
        let count = outline.pageRows.count
        app.typeKey("n", modifierFlags: .command)
        let added = NSPredicate { _, _ in self.outline.pageRows.count == count + 1 }
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

    private func waitFor(_ condition: @autoclosure @escaping () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, message, file: file, line: line)
    }
}
