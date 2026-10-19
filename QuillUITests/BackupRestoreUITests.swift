import XCTest

/// Backup wiederherstellen (ADR-019) über drei Starts: Stand sichern, ändern,
/// Backup wählen, Quill beendet sich, der nächste Start spielt es ein und meldet es.
/// Die Datenbank liegt in einem eigenen Ordner im temporären Ordner der App
/// (`-QuillStoreDirectory`), nie im echten Store. Die Dateischritte prüfen die
/// Unit-Tests in `StoreRestoreTests`.
@MainActor
final class BackupRestoreUITests: XCTestCase {
    private var app: XCUIApplication!
    private let storeDirectory = "uitest-restore-\(UUID().uuidString)"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        app?.terminate()
    }

    func testRestoreBackupAcrossRelaunch() throws {
        // 1. Stand „Alt“; beim Beenden entsteht das Backup.
        launch()
        createPage("Alt")
        quit()

        // 2. Ändern, dann das Backup „Beim Beenden“ wiederherstellen.
        launch()
        assertTitles(["Alt"])
        createPage("Neu")
        assertTitles(["Alt", "Neu"])
        let sheet = openRestoreSheet()
        let row = sheet.descendants(matching: .any).matching(identifier: "restore.row")
            .containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Beim Beenden", "Beim Beenden")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Kein Backup „Beim Beenden“")
        row.click()
        sheet.buttons["restore.confirm"].click()
        let confirm = app.windows.firstMatch.descendants(matching: .button).matching(identifier: "Wiederherstellen und beenden").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        let quitted = app.wait(for: .notRunning, timeout: 30)
        let error = sheet.descendants(matching: .any)["restore.error"]
        XCTAssertTrue(quitted, "Quill beendet sich nicht: \(error.exists ? error.label : "ohne Fehlermeldung")")

        // 3. Der Start spielt das Backup ein und sagt welches.
        launch(dismissingAlert: false)
        let alert = app.windows.firstMatch.sheets.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "Keine Meldung nach dem Start")
        let message = alert.descendants(matching: .any).allElementsBoundByIndex
            .flatMap { [$0.label, $0.value as? String ?? ""] }.joined(separator: "\n")
        XCTAssertTrue(message.contains("Backup wiederhergestellt"), message)
        XCTAssertTrue(message.contains("(Beim Beenden)"), message)
        XCTAssertTrue(message.contains("Application Support/Quill/Backups/"), "Ort des vorherigen Stands fehlt: \(message)")
        alert.buttons["OK"].click()
        assertTitles(["Alt"])

        // Der vorherige Stand ist als Backup da und könnte zurückgeholt werden.
        let again = openRestoreSheet()
        let safety = again.descendants(matching: .any).matching(identifier: "restore.row")
            .containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Vor dem Wiederherstellen", "Vor dem Wiederherstellen")).firstMatch
        XCTAssertTrue(safety.waitForExistence(timeout: 5), "Kein Backup „Vor dem Wiederherstellen“")
        again.buttons["Abbrechen"].click()
    }

    // MARK: - Hilfen

    private func launch(dismissingAlert: Bool = true) {
        app = XCUIApplication.quill(storeDirectory: storeDirectory)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        if dismissingAlert {
            app.windows.firstMatch.click()
        }
    }

    private func quit() {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 30), "Quill beendet sich nicht")
    }

    private func openRestoreSheet() -> XCUIElement {
        app.menuBars.menuBarItems["Ablage"].click()
        app.menuBars.menuItems["Backup wiederherstellen …"].click()
        let sheet = app.windows.firstMatch.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Kein Fenster „Backup wiederherstellen“")
        return sheet
    }

    private var outline: XCUIElement {
        app.windows.firstMatch.outlines["sidebar.pages"]
    }

    private func titles() -> [String] {
        outline.pageRows.allElementsBoundByIndex.map { $0.textFields.firstMatch.value as? String ?? "" }
    }

    /// ⌘N, dann Titel tippen (wie in `SidebarUITests`).
    private func createPage(_ title: String) {
        let count = outline.pageRows.count
        app.typeKey("n", modifierFlags: .command)
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
        let matches = NSPredicate { _, _ in Set(self.titles()) == Set(expected) && self.titles().count == expected.count }
        let result = XCTWaiter.wait(for: [expectation(for: matches, evaluatedWith: nil)], timeout: 10)
        XCTAssertEqual(result, .completed, "Sidebar: \(titles()) statt \(expected)", file: file, line: line)
    }
}
