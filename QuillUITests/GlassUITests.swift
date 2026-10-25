import XCTest

/// Einstellungen › Darstellung › Liquid Glass (ADR-036): „Wie System“, Regler und
/// „Transparenz reduzieren“. Im Test-Store liest und speichert die App die Wahl des
/// Nutzers nie (`EditorThemeSetup`); Speichern und Laden prüft `GlassTests`.
@MainActor
final class GlassUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.quill()
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private func launch(_ arguments: [String] = []) {
        app.launchArguments += arguments
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    /// ⌘, öffnet die Einstellungen; liefert den Schalter „Wie System“.
    private func openSettings() -> XCUIElement {
        app.typeKey(",", modifierFlags: .command)
        app.toolbars.buttons["Darstellung"].click()
        let toggle = app.descendants(matching: .any)["settings.glass.followsSystem"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Einstellungen nicht geöffnet")
        return toggle
    }

    private var slider: XCUIElement { app.sliders["settings.glass.slider"] }
    private var hint: XCUIElement { app.descendants(matching: .any)["settings.glass.reduceTransparency"] }

    /// Stufe des Reglers; VoiceOver liest dazu „Klar“ … „Getönt“ (`GlassSettingsRowTests`).
    private var level: Double? {
        (slider.value as? NSNumber)?.doubleValue ?? (slider.value as? String).flatMap(Double.init)
    }

    private func isOn(_ toggle: XCUIElement) -> Bool {
        (toggle.value as? NSNumber)?.boolValue ?? (toggle.value as? String == "1")
    }

    func testFollowsSystemByDefaultThenSliderWorksLive() throws {
        launch()
        app.typeKey("n", modifierFlags: .command)
        app.typeText("Glas\r")
        app.typeText("Text bleibt gleich")
        let editor = app.windows.firstMatch.textViews["editor.text"]
        let before = editor.value as? String
        let rows = app.windows.firstMatch.outlines["sidebar.pages"].cells.count

        let toggle = openSettings()
        XCTAssertTrue(isOn(toggle), "„Wie System“ ist Standard")
        XCTAssertTrue(slider.exists)
        XCTAssertFalse(slider.isEnabled, "Regler ausgegraut bei „Wie System“")
        XCTAssertFalse(hint.exists)

        toggle.click()
        XCTAssertFalse(isOn(toggle))
        XCTAssertTrue(slider.isEnabled)
        XCTAssertEqual(level, 0.5, "Standard Mitte")
        XCTAssertEqual(slider.label, "Liquid Glass")
        slider.adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(level, 0)
        slider.adjust(toNormalizedSliderPosition: 0.8)
        XCTAssertEqual(level, 0.75, "rastet auf Stufen von 25 %")
        slider.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(level, 1)

        toggle.click()
        XCTAssertTrue(isOn(toggle))
        XCTAssertFalse(slider.isEnabled)

        // Einstellungen schließen: Text unverändert, Sidebar und Editor weiter bedienbar.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, before)
        XCTAssertEqual(app.windows.firstMatch.outlines["sidebar.pages"].cells.count, rows)
    }

    /// Startargument: Stufe ohne „Wie System“; „Transparenz reduzieren“ graut den Regler
    /// aus und zeigt den Hinweis.
    func testReduceTransparencyWinsAndShowsAHint() throws {
        launch(["-QuillTestGlass", "0.25", "-QuillTestReduceTransparency", "YES"])
        let toggle = openSettings()
        XCTAssertFalse(isOn(toggle))
        XCTAssertEqual(level, 0.25)
        XCTAssertFalse(slider.isEnabled, "„Transparenz reduzieren“ hat Vorrang")
        XCTAssertTrue(hint.exists)
        let text = "\(hint.label) \(hint.value ?? "")"
        XCTAssertTrue(text.contains("Transparenz reduzieren"), text)

        // Auch mit „Wie System“ bleibt der Hinweis; der Regler bleibt aus.
        toggle.click()
        XCTAssertTrue(isOn(toggle))
        XCTAssertTrue(hint.exists)
        XCTAssertFalse(slider.isEnabled)
    }
}
