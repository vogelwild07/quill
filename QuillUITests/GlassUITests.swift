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
        let toggle = app.descendants(matching: .any)["settings.glass.followsSystem"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Einstellungen nicht geöffnet")
        return toggle
    }

    private var slider: XCUIElement { app.sliders["settings.glass.slider"] }
    private var hint: XCUIElement { app.descendants(matching: .any)["settings.glass.reduceTransparency"] }

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

        let toggle = openSettings()
        XCTAssertTrue(isOn(toggle), "„Wie System“ ist Standard")
        XCTAssertTrue(slider.exists)
        XCTAssertFalse(slider.isEnabled, "Regler ausgegraut bei „Wie System“")
        XCTAssertFalse(hint.exists)

        toggle.click()
        XCTAssertFalse(isOn(toggle))
        XCTAssertTrue(slider.isEnabled)
        XCTAssertEqual(slider.value as? String, "50 % getönt", "Standard Mitte")
        slider.adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(slider.value as? String, "Klar")
        slider.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(slider.value as? String, "Getönt")

        toggle.click()
        XCTAssertTrue(isOn(toggle))
        XCTAssertFalse(slider.isEnabled)

        // Einstellungen schließen: Text unverändert, Sidebar und Editor weiter bedienbar.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, before)
        XCTAssertEqual(app.windows.firstMatch.outlines["sidebar.pages"].cells.count, 1)
    }

    /// Startargument: Stufe ohne „Wie System“; „Transparenz reduzieren“ graut den Regler
    /// aus und zeigt den Hinweis.
    func testReduceTransparencyWinsAndShowsAHint() throws {
        launch(["-QuillTestGlass", "0.25", "-QuillTestReduceTransparency", "YES"])
        let toggle = openSettings()
        XCTAssertFalse(isOn(toggle))
        XCTAssertEqual(slider.value as? String, "25 % getönt")
        XCTAssertFalse(slider.isEnabled, "„Transparenz reduzieren“ hat Vorrang")
        XCTAssertTrue(hint.exists)
        XCTAssertTrue(hint.label.contains("Transparenz reduzieren"), hint.label)

        // Auch mit „Wie System“ bleibt der Hinweis; der Regler bleibt aus.
        toggle.click()
        XCTAssertTrue(isOn(toggle))
        XCTAssertTrue(hint.exists)
        XCTAssertFalse(slider.isEnabled)
    }
}
