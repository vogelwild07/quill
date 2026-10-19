import XCTest

/// Markdown-Export (ADR-018) über Menü, Kürzel und Kontextmenü. Der Ordnerdialog
/// läuft in der Sandbox außerhalb der App; `-QuillExportDirectory` lässt die App
/// stattdessen in ihren eigenen temporären Ordner schreiben. Inhalt und Aufbau der
/// Dateien prüfen die Unit-Tests in `QuillExportTests`, hier nur die Rückmeldung.
@MainActor
final class ExportUITests: XCTestCase {
    private var app: XCUIApplication!

    // Die async-Varianten laufen auf dem Main Actor wie die XCUITest-APIs;
    // `setUpWithError`/`tearDownWithError` wären nonisolated.
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.quill()
        app.launchArguments += ["-QuillExportDirectory", "uitest-\(UUID().uuidString)"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.windows.firstMatch.click()
    }

    override func tearDown() async throws {
        app.terminate()
    }

    func testExportViaMenuShortcutAndContextMenu() throws {
        createPage("Projekte")
        createPage("Quill", subpage: true)
        assertTitles(["Projekte", "Quill"])
        let folder = "Projekte (Quill \(Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))))"

        // Menü „Seite“: Seite mit Unterseite.
        row(0).click()
        app.menuBars.menuBarItems["Seite"].click()
        app.menuBars.menuItems["Exportieren …"].click()
        assertReport(["„Projekte“ exportiert", "Seiten: 2 · Bilder: 0", "Ordner: \(folder)"])

        // ⇧⌘E: Der vorhandene Ordner wird nicht überschrieben.
        app.typeKey("e", modifierFlags: [.command, .shift])
        assertReport(["Ordner: \(folder) 2"])

        // Kontextmenü an der Unterseite: nur sie.
        row(1).rightClick()
        outline.menuItems["Exportieren …"].click()
        assertReport(["„Quill“ exportiert", "Seiten: 1 · Bilder: 0"])
    }

    // MARK: - Hilfen

    /// Wartet auf die Meldung, prüft ihre Zeilen und schließt sie mit „OK“.
    private func assertReport(_ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        let sheet = app.windows.firstMatch.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "Keine Meldung", file: file, line: line)
        let texts = sheet.staticTexts.allElementsBoundByIndex
            .flatMap { ($0.value as? String ?? $0.label).components(separatedBy: "\n") }
        for text in expected {
            XCTAssertTrue(texts.contains(text), "„\(text)“ fehlt in \(texts)", file: file, line: line)
        }
        sheet.buttons["OK"].click()
        let gone = NSPredicate { _, _ in !sheet.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: gone, evaluatedWith: nil)], timeout: 5), .completed, "Meldung bleibt offen", file: file, line: line)
    }

    private var outline: XCUIElement {
        app.windows.firstMatch.outlines["sidebar.pages"]
    }

    private func row(_ index: Int) -> XCUIElement {
        outline.pageRows.element(boundBy: index)
    }

    private func titles() -> [String] {
        outline.pageRows.allElementsBoundByIndex.map { $0.textFields.firstMatch.value as? String ?? "" }
    }

    /// ⌘N bzw. ⇧⌘N, dann Titel tippen (wie in `SidebarUITests`).
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

    private func assertTitles(_ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        let matches = NSPredicate { _, _ in self.titles() == expected }
        let result = XCTWaiter.wait(for: [expectation(for: matches, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, "Sidebar: \(titles()) statt \(expected)", file: file, line: line)
    }
}
