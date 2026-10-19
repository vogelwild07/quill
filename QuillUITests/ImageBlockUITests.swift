import AppKit
import XCTest

/// Bild-Block: Einsetzen aus der Zwischenablage, Undo, Seitenwechsel, Hinweis beim
/// Verkleinern. Die App nutzt eine eigene Zwischenablage (`-QuillPasteboardName`),
/// die des Nutzers bleibt unberührt. Das Testbild erzeugt die App selbst
/// (`-QuillTestImage`): Füllte der Test-Runner die Zwischenablage, sperrte der
/// Datenschutz („Einsetzen aus anderen Apps“) das Einsetzen.
/// Ein Bild-Block steht im Text der Bedienungshilfen als U+FFFC.
/// Die Dateiauswahl (Slash-Menü „Bild“) läuft in der Sandbox außerhalb der App und
/// wird von Hand geprüft; hier nur der Eintrag im Menü.
@MainActor
final class ImageBlockUITests: XCTestCase {
    private var app: XCUIApplication!
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.vogelwild07.quill.uitests.\(UUID().uuidString)"))
    private let image = "\u{FFFC}"

    // Die async-Varianten laufen auf dem Main Actor wie die XCUITest-APIs;
    // `setUpWithError`/`tearDownWithError` wären nonisolated.
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Startet die App; mit `image` (`<Breite>x<Höhe>` oder `heavy`) liegt das
    /// Testbild dann in ihrer Zwischenablage.
    private func launch(image: String? = nil) {
        app = XCUIApplication.quill()
        app.launchArguments += ["-QuillPasteboardName", pasteboard.name.rawValue]
        if let image { app.launchArguments += ["-QuillTestImage", image] }
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.windows.firstMatch.click()
    }

    override func tearDown() async throws {
        app?.terminate()
        pasteboard.releaseGlobally()
    }

    // MARK: - Tests

    func testPastedImageIsUndoableAndSurvivesPageSwitch() throws {
        let generalChangeCount = NSPasteboard.general.changeCount
        launch(image: "120x60")
        createPage("Bilder")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Oben\r")
        app.typeKey("v", modifierFlags: .command)
        assertEditorText("Oben\n\(image)\n\n")

        app.typeKey("z", modifierFlags: .command)
        assertEditorText("Oben\n\n")
        app.typeKey("z", modifierFlags: [.command, .shift])
        assertEditorText("Oben\n\(image)\n\n")

        // Seitenwechsel: gespeichert und mit Bild wieder geladen.
        createPage("Andere")
        row(0).click()
        assertEditorText("Oben\n\(image)\n\n")
        XCTAssertEqual(NSPasteboard.general.changeCount, generalChangeCount, "Allgemeine Zwischenablage wurde verändert")
    }

    func testPastingImageOverSelectionIsOneUndoStep() throws {
        launch(image: "40x40")
        createPage("Auswahl")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Hallo Welt")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("v", modifierFlags: .command)
        assertEditorText("\(image)\n\n")

        app.typeKey("z", modifierFlags: .command)
        assertEditorText("Hallo Welt\n")
    }

    /// Bild über 20 MB (`heavy`, `TestImageTests` prüft die Größe).
    func testHeavyImageShowsDownscaleNotice() throws {
        launch(image: "heavy")
        createPage("Groß")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeKey("v", modifierFlags: .command)
        assertEditorText("\(image)\n\n")

        let notice = app.descendants(matching: .any)["editor.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 20), "Kein Hinweis: \(app.windows.firstMatch.debugDescription)")
        XCTAssertEqual(notice.label, "Bild wurde verkleinert")
    }

    func testSlashMenuOffersImage() throws {
        launch()
        createPage("Slash")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("/bild")
        let entry = app.descendants(matching: .any)["slash.image"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(entry.label, "Bild")
        app.typeKey(.escape, modifierFlags: [])
        assertEditorText("/bild\n")
    }

    // MARK: - Hilfen (wie in `EditorUITests`)

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
        outline.pageRows.element(boundBy: index)
    }

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
        let result = XCTWaiter.wait(for: [expectation(for: matches, evaluatedWith: nil)], timeout: 10)
        XCTAssertEqual(result, .completed, "Editor: \((editor.value as? String)?.debugDescription ?? "nil") statt \(expected.debugDescription)", file: file, line: line)
    }
}
