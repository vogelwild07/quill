import XCTest

/// Fokus-Modus (Phase 18.1): Darstellung › Fokus-Modus (⇧⌘F) und der Schalter unter
/// Einstellungen › Darstellung zeigen denselben Zustand. Im Test-Store liest und
/// speichert die App die Wahl des Nutzers nie (`EditorThemeSetup`); Abdunkeln und
/// Scrollen prüfen `EditorFocusModeTests` aus dem Package heraus.
@MainActor
final class FocusModeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.quill()
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private func launch(focusMode: Bool = false) {
        if focusMode { app.launchArguments += ["-QuillTestFocusMode", "YES"] }
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    /// ⌘, öffnet die Einstellungen; liefert den Schalter für den Fokus-Modus.
    private func openSettings() -> XCUIElement {
        app.typeKey(",", modifierFlags: .command)
        app.toolbars.buttons["Darstellung"].click()
        let toggle = app.descendants(matching: .any)["settings.focusMode"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Einstellungen nicht geöffnet")
        return toggle
    }

    private func isOn(_ toggle: XCUIElement) -> Bool {
        (toggle.value as? NSNumber)?.boolValue ?? (toggle.value as? String == "1")
    }

    func testShortcutMenuAndSettingsShareTheStateWithoutTouchingText() throws {
        launch()
        XCTAssertTrue(app.menuBars.menuItems["Fokus-Modus"].exists, "Menüpunkt fehlt")
        app.typeKey("n", modifierFlags: .command)
        app.typeText("Fokus\r")
        app.typeText("Text bleibt gleich")
        let editor = app.windows.firstMatch.textViews["editor.text"]
        let before = editor.value as? String

        app.typeKey("f", modifierFlags: [.command, .shift])
        let toggle = openSettings()
        XCTAssertTrue(isOn(toggle), "⇧⌘F schaltet ein")
        toggle.click()
        XCTAssertFalse(isOn(toggle), "Schalter schaltet aus")
        toggle.click()
        XCTAssertTrue(isOn(toggle))

        // Einstellungen schließen: Text unverändert, Undo betrifft nur Getipptes.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, before)
        editor.click()
        app.typeText(" und mehr")
        let typed = editor.value as? String
        app.typeKey("z", modifierFlags: .command)
        // Undo nimmt Getipptes zurück (Tippen wird zusammengefasst), nicht den Schalter.
        XCTAssertNotEqual(editor.value as? String, typed)
        XCTAssertFalse((editor.value as? String ?? "").contains("und mehr"))

        app.typeKey("f", modifierFlags: [.command, .shift])
        XCTAssertFalse(isOn(openSettings()), "⇧⌘F schaltet wieder aus")
    }

    /// Startargument gilt nur im Test-Store.
    func testLaunchArgumentEnablesFocusMode() throws {
        launch(focusMode: true)
        XCTAssertTrue(isOn(openSettings()))
        app.terminate()

        app = XCUIApplication.quill()
        launch()
        XCTAssertFalse(isOn(openSettings()))
    }
}
