import XCTest

/// Rückfrage vor der Migration auf ein neues Schema (Phase 11.2, ADR-029): Return und
/// Escape beenden, ohne etwas zu verändern; nur ein Klick auf „Umstellen“ migriert. Der Store liegt im temporären Ordner der App (`-QuillStoreDirectory`) und
/// beginnt im alten Format V1 (`-QuillSeedSchemaV1`); `-QuillAskBeforeMigration` fragt
/// wie beim echten Store. Die Dateischritte prüft `MigrationPromptTests`.
@MainActor
final class MigrationPromptUITests: XCTestCase {
    private var app: XCUIApplication!
    private let storeDirectory = "uitest-migration-\(UUID().uuidString)"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        app?.terminate()
    }

    func testReturnAndEscapeQuitAndOnlyAClickMigrates() throws {
        // 1. Return wählt „Beenden“: Quill endet ohne Fenster.
        launch()
        let quit = app.buttons["migration.quit"]
        XCTAssertTrue(quit.waitForExistence(timeout: 10), "Keine Rückfrage vor der Migration")
        XCTAssertTrue(app.buttons["migration.migrate"].exists)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "Return beendet Quill nicht")

        // 2. Nicht umgestellt: Die Rückfrage kommt wieder. Escape wählt auch „Beenden“.
        launch()
        XCTAssertTrue(app.buttons["migration.quit"].waitForExistence(timeout: 10), "Store wurde ohne Zustimmung umgestellt")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "Escape beendet Quill nicht")

        // 3. Klick auf „Umstellen“: Quill öffnet mit dem alten Bestand.
        launch()
        let migrate = app.buttons["migration.migrate"]
        XCTAssertTrue(migrate.waitForExistence(timeout: 10), "Store wurde ohne Zustimmung umgestellt")
        migrate.click()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        assertSidebarContains("Projekte")
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 30), "Quill beendet sich nicht")

        // 4. Nach der Umstellung keine Rückfrage mehr.
        launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["migration.quit"].exists, "Rückfrage nach der Umstellung")
        assertSidebarContains("Projekte")
    }

    // MARK: - Hilfen

    private func launch() {
        app = XCUIApplication.quill(storeDirectory: storeDirectory)
        app.launchArguments += ["-QuillSeedSchemaV1", "YES", "-QuillAskBeforeMigration", "YES"]
        app.launch()
    }

    private func assertSidebarContains(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let outline = app.windows.firstMatch.outlines["sidebar.pages"]
        let titles = { outline.pageRows.allElementsBoundByIndex.map { $0.textFields.firstMatch.value as? String ?? "" } }
        let found = NSPredicate { _, _ in titles().contains(title) }
        let result = XCTWaiter.wait(for: [expectation(for: found, evaluatedWith: nil)], timeout: 10)
        XCTAssertEqual(result, .completed, "Sidebar: \(titles()) ohne \(title)", file: file, line: line)
    }
}
