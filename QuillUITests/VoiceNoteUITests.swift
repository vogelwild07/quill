import XCTest

/// Sprachnotiz (17.2, ADR-034). Test-Stores nehmen nie über das Mikrofon auf, sondern
/// lesen einen festen Text aus dem Speicher („Milch und Brot kaufen.“).
@MainActor
final class VoiceNoteUITests: XCTestCase {
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

    func testRecordStopAndInsert() throws {
        createPage("Einkauf")

        // Ohne Einfügemarke im Editor: Hinweis statt Blatt.
        openVoiceNote()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Kein Hinweis ohne Einfügemarke")
        XCTAssertTrue(sheet.staticTexts["Setze die Einfügemarke in eine Seite."].exists)
        sheet.buttons.firstMatch.click()
        waitFor(!self.sheet.exists, "Hinweis bleibt offen")

        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Liste")
        openVoiceNote()
        let record = sheet.buttons["voice.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5), "Kein Blatt „Sprachnotiz“")
        XCTAssertFalse(sheet.buttons["voice.insert"].isEnabled, "„Einfügen“ ohne Text")
        record.click()

        let stop = sheet.buttons["voice.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "Kein „Stopp“ während der Aufnahme")
        waitFor(self.transcript.contains("Milch und Brot kaufen."), "Keine Abschrift: \(transcript)")
        XCTAssertFalse(sheet.buttons["voice.insert"].isEnabled, "„Einfügen“ während der Aufnahme")
        stop.click()

        let insert = sheet.buttons["voice.insert"]
        waitFor(insert.isEnabled, "„Einfügen“ bleibt nach „Stopp“ gesperrt")
        XCTAssertTrue(sheet.buttons["voice.record"].exists, "Kein „Aufnehmen“ nach „Stopp“")
        insert.click()
        waitFor(!self.sheet.exists, "Blatt bleibt nach „Einfügen“ offen")
        waitFor(self.editorText == "Liste\nMilch und Brot kaufen.\n", "Nicht eingefügt: \(editorText)")

        app.typeKey("z", modifierFlags: .command)
        waitFor(self.editorText == "Liste\n", "⌘Z nimmt die Sprachnotiz nicht zurück: \(editorText)")

        // „Abbrechen“ verwirft die Abschrift.
        openVoiceNote()
        XCTAssertTrue(sheet.buttons["voice.record"].waitForExistence(timeout: 5))
        sheet.buttons["voice.record"].click()
        waitFor(self.transcript.contains("Milch"), "Keine Abschrift: \(transcript)")
        app.typeKey(.escape, modifierFlags: [])
        waitFor(!self.sheet.exists, "Blatt bleibt nach „Abbrechen“ offen")
        XCTAssertEqual(editorText, "Liste\n")
    }

    private var editor: XCUIElement {
        app.windows.firstMatch.textViews["editor.text"]
    }

    private var editorText: String {
        editor.value as? String ?? ""
    }

    private var sheet: XCUIElement {
        app.windows.firstMatch.sheets.firstMatch
    }

    private var transcript: String {
        sheet.staticTexts["voice.transcript"].value as? String ?? ""
    }

    private var outline: XCUIElement {
        app.windows.firstMatch.outlines["sidebar.pages"]
    }

    private func openVoiceNote() {
        app.menuBars.menuBarItems["Format"].click()
        app.menuBars.menuItems["Sprachnotiz …"].click()
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
