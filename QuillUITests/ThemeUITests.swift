import XCTest

/// Einstellungen › Darstellung (ADR-024): Liste der Themes, Wechsel wirkt sofort.
/// Im Test-Store liest und speichert die App das Theme des Nutzers nie
/// (`EditorThemeSetup`); Farben selbst prüfen `EditorThemeTests` aus der App heraus.
@MainActor
final class ThemeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.quill()
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private func launch(theme: String? = nil) {
        if let theme { app.launchArguments += ["-QuillEditorTheme", theme] }
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    /// ⌘, öffnet die Einstellungen; das Label der Vorschau nennt das Theme.
    private func openSettings() -> XCUIElement {
        app.typeKey(",", modifierFlags: .command)
        let preview = app.descendants(matching: .any)["settings.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "Einstellungen nicht geöffnet")
        return preview
    }

    func testSettingsListAllThemesAndSwitchLive() throws {
        launch()
        // Seite mit Text: Ein Wechsel darf ihn nicht ändern und kein Undo anlegen.
        app.typeKey("n", modifierFlags: .command)
        app.typeText("Farben\r")
        app.typeText("Text bleibt gleich")
        let editor = app.windows.firstMatch.textViews["editor.text"]
        let before = editor.value as? String

        let preview = openSettings()
        XCTAssertEqual(preview.label, "Vorschau: Standard")
        for id in ["standard", "quill", "tinte", "sonne", "lagune", "abend", "kontrast"] {
            XCTAssertTrue(app.descendants(matching: .any)["settings.theme.\(id)"].exists, id)
        }

        app.descendants(matching: .any)["settings.theme.lagune"].click()
        XCTAssertEqual(preview.label, "Vorschau: Lagune")
        app.descendants(matching: .any)["settings.theme.sonne"].click()
        XCTAssertEqual(preview.label, "Vorschau: Sonne")

        // Einstellungen schließen, Editor unverändert und weiter bedienbar.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, before)
        editor.click()
        app.typeKey("z", modifierFlags: .command)
        // Undo nimmt Getipptes zurück, nicht den Theme-Wechsel: Der Text wird kürzer.
        XCTAssertNotEqual(editor.value as? String, before)
    }

    /// Startargument gilt nur im Test-Store; Unbekanntes ergibt Standard.
    func testLaunchArgumentSelectsTheme() throws {
        launch(theme: "abend")
        XCTAssertEqual(openSettings().label, "Vorschau: Abend")
        app.terminate()

        app = XCUIApplication.quill()
        launch(theme: "neon")
        XCTAssertEqual(openSettings().label, "Vorschau: Standard")
    }
}
