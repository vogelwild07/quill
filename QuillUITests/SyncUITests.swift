import XCTest

/// Einstellungen › Sync und die Rückfrage nach einem eingespielten Backup (ADR-029).
/// Ordner nur im temporären Ordner der App (`-QuillSyncTestFolder`, ersetzt die
/// Dateiauswahl), Store nur im Test-Store; die Einstellungen des Sync liegen dann im
/// Arbeitsspeicher bzw. im Testordner, nie in denen des Macs. Abgleich und Ordner
/// prüfen die Unit-Tests (`SyncEngineTests`, `SyncControllerTests`).
@MainActor
final class SyncUITests: XCTestCase {
    private var app: XCUIApplication!
    private let storeDirectory = "uitest-sync-\(UUID().uuidString)"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        app?.terminate()
    }

    func testEnablePauseAndTurnOff() throws {
        app = XCUIApplication.quill()
        app.launchArguments += ["-QuillSyncTestFolder", "uitest-syncfolder-\(UUID().uuidString)"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        // Aus, bis der Nutzer einen Ordner wählt.
        openSyncSettings()
        let enable = app.buttons["sync.enable"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5), "Sync nicht aus")
        enable.click()
        waitForStatus("Abgeglichen")

        let pause = app.descendants(matching: .any)["sync.pause"]
        pause.click()
        waitForStatus("Pausiert")
        XCTAssertFalse(app.buttons["sync.now"].isEnabled, "Abgleichen trotz Pause möglich")
        pause.click()
        waitForStatus("Abgeglichen")

        app.buttons["sync.turnOff"].click()
        let confirm = app.buttons["sync.turnOff.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(enable.waitForExistence(timeout: 5), "Sync nicht ausgeschaltet")
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "bisherigen Ordner", "bisherigen Ordner")).firstMatch.exists,
            "Kein Hinweis auf den bisherigen Ordner"
        )
    }

    /// Backup einspielen schaltet den Sync aus; nach dem Neustart fragt Quill, und
    /// „Neu beginnen …“ verbindet mit einem neuen, leeren Ordner.
    func testRestoreTurnsSyncOffAndAsksAfterRelaunch() throws {
        launch(syncFolder: "uitest-syncfolder-a-\(UUID().uuidString)")
        openSyncSettings()
        app.buttons["sync.enable"].click()
        waitForStatus("Abgeglichen")
        app.typeKey("w", modifierFlags: .command)

        // Das Backup vor dem Einschalten wählen; die Bestätigung nennt den Sync.
        app.windows.firstMatch.click()
        app.menuBars.menuBarItems["Ablage"].click()
        app.menuBars.menuItems["Backup wiederherstellen …"].click()
        let sheet = app.windows.firstMatch.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let row = sheet.descendants(matching: .any).matching(identifier: "restore.row")
            .containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Vor dem Einschalten des Sync", "Vor dem Einschalten des Sync")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Kein Backup „Vor dem Einschalten des Sync“")
        row.click()
        sheet.buttons["restore.confirm"].click()
        let note = app.staticTexts.containing(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Der Sync wird dafür ausgeschaltet", "Der Sync wird dafür ausgeschaltet")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "Bestätigung nennt den Sync nicht")
        app.windows.firstMatch.descendants(matching: .button).matching(identifier: "Wiederherstellen und beenden").firstMatch.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 30), "Quill beendet sich nicht")

        // Nach der Meldung zum Backup die Rückfrage; nichts ist Standard für Return.
        let newFolder = "uitest-syncfolder-b-\(UUID().uuidString)"
        launch(syncFolder: newFolder)
        let notice = app.windows.firstMatch.sheets.firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "Keine Meldung nach dem Start")
        notice.buttons["OK"].click()
        let startOver = app.buttons["syncReconnect.startOver"]
        XCTAssertTrue(startOver.waitForExistence(timeout: 10), "Keine Rückfrage zum Sync")
        XCTAssertTrue(app.buttons["syncReconnect.merge"].exists)
        XCTAssertTrue(app.buttons["syncReconnect.later"].exists)
        startOver.click()
        XCTAssertTrue(startOver.waitForNonExistence(timeout: 10), "Rückfrage bleibt offen")

        openSyncSettings()
        waitForStatus("Abgeglichen")
        let folder = app.staticTexts.containing(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", newFolder, newFolder)).firstMatch
        XCTAssertTrue(folder.exists, "Nicht mit dem neuen Ordner verbunden")
    }

    // MARK: - Hilfen

    private func launch(syncFolder: String) {
        app = XCUIApplication.quill(storeDirectory: storeDirectory)
        app.launchArguments += ["-QuillSyncTestFolder", syncFolder]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    /// ⌘, und dort der Bereich „Sync“.
    private func openSyncSettings() {
        app.typeKey(",", modifierFlags: .command)
        let tab = app.toolbars.buttons["Sync"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Kein Bereich „Sync“ in den Einstellungen")
        tab.click()
    }

    private func waitForStatus(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let status = app.descendants(matching: .any)["sync.status"]
        let matches = NSPredicate { _, _ in
            status.exists && (status.label.contains(text) || (status.value as? String ?? "").contains(text))
        }
        let result = XCTWaiter.wait(for: [expectation(for: matches, evaluatedWith: nil)], timeout: 15)
        XCTAssertEqual(result, .completed, "Status „\(status.exists ? status.label : "fehlt")“ statt „\(text)“", file: file, line: line)
    }
}
