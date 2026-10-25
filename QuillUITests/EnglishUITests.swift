import XCTest

/// Oberfläche auf Englisch (ADR-038). Sprache und Region gelten nur für den Start der App;
/// alle anderen UI-Tests laufen fest auf Deutsch.
@MainActor
final class EnglishUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        app?.terminate()
    }

    private func launch(_ languages: [String], region: String) {
        app = XCUIApplication.quill(languages: languages, region: region)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.windows.firstMatch.click()
    }

    private var window: XCUIElement { app.windows.firstMatch }

    /// Leerzustand, Menüs von Quill und AppKit, Einstellungen.
    func testEmptyStateMenusAndSettings() throws {
        launch(["en"], region: "US")
        let sidebarEmpty = window.staticTexts["sidebar.emptyState.title"]
        XCTAssertTrue(sidebarEmpty.waitForExistence(timeout: 5))
        XCTAssertEqual(sidebarEmpty.value as? String, "No Pages Yet")
        XCTAssertEqual(window.staticTexts["detail.emptyState.title"].value as? String, "No Page Selected")
        XCTAssertEqual(window.buttons["detail.emptyState.action"].label, "New Page")

        for menu in ["File", "Edit", "Format", "View", "Page", "Window", "Help"] {
            XCTAssertTrue(app.menuBars.menuBarItems[menu].exists, "Menü „\(menu)“ fehlt")
        }
        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(app.menuBars.menuItems["Restore Backup…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuBars.menuItems["Quick Open…"].exists)
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.toolbars.buttons["General"].waitForExistence(timeout: 5))
        for tab in ["Appearance", "Sync", "Time Travel", "Licenses"] {
            XCTAssertTrue(app.toolbars.buttons[tab].exists, "Reiter „\(tab)“ fehlt")
        }
        XCTAssertEqual(app.descendants(matching: .any)["settings.updates.lastChecked"].value as? String, "Never")
        app.toolbars.buttons["Appearance"].click()
        let preview = app.descendants(matching: .any)["settings.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.label.hasPrefix("Preview: "), preview.label)
        app.typeKey("w", modifierFlags: .command)
    }

    /// Slash-Menü auf Englisch; die Suche findet auch die deutschen Namen. Die Tagesseite
    /// legt „Days“ und den Tag mit englischem Datum an.
    func testSlashMenuAndTodayPage() throws {
        launch(["en"], region: "US")
        app.typeKey("n", modifierFlags: .command)
        let title = window.descendants(matching: .any)["detail.title"]
        let focused = NSPredicate { _, _ in title.value(forKey: "hasKeyboardFocus") as? Bool == true }
        wait(for: [expectation(for: focused, evaluatedWith: nil)], timeout: 5)
        app.typeText("Plan\r")

        app.typeText("/")
        let menu = app.descendants(matching: .any)["slash.menu"]
        let heading = menu.descendants(matching: .any)["slash.heading1"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5), "Slash-Menü nicht offen")
        XCTAssertEqual(heading.label, "Heading 1")
        app.typeText("überschr")
        XCTAssertTrue(heading.waitForExistence(timeout: 5), "Deutscher Name findet die Überschrift nicht")
        XCTAssertFalse(menu.descendants(matching: .any)["slash.todo"].exists)
        app.typeKey(.escape, modifierFlags: [])

        let day = Date.now.formatted(Date.FormatStyle(locale: Locale(identifier: "en_US")).weekday(.wide).day().month(.wide).year())
        app.typeKey("t", modifierFlags: [.command, .shift])
        let opened = NSPredicate { _, _ in self.window.title == day }
        wait(for: [expectation(for: opened, evaluatedWith: nil)], timeout: 10)
        let outline = window.outlines["sidebar.pages"]
        XCTAssertTrue(outline.pageRows.containing(NSPredicate(format: "value == %@", "Days")).firstMatch.waitForExistence(timeout: 5),
                      "Keine Sammelseite „Days“")
    }

    /// Andere Sprachen: Steht Englisch weiter unten in der Liste, zeigt Quill Englisch; ohne
    /// Deutsch und Englisch die Ausgangssprache Deutsch. App (Menüs von AppKit) und Pakete
    /// entscheiden dabei immer gleich, nie gemischt.
    func testOtherLanguagesUseTheNextLanguageInTheList() throws {
        launch(["fr", "en"], region: "FR")
        let sidebarEmpty = window.staticTexts["sidebar.emptyState.title"]
        XCTAssertTrue(sidebarEmpty.waitForExistence(timeout: 5))
        XCTAssertEqual(sidebarEmpty.value as? String, "No Pages Yet")
        XCTAssertTrue(app.menuBars.menuBarItems["Page"].exists, "Menü von Quill nicht auf Englisch")
        XCTAssertTrue(app.menuBars.menuBarItems["Edit"].exists, "Menü von AppKit nicht auf Englisch")
        app.terminate()

        launch(["fr"], region: "FR")
        XCTAssertTrue(sidebarEmpty.waitForExistence(timeout: 5))
        XCTAssertEqual(sidebarEmpty.value as? String, "Noch keine Seiten")
        XCTAssertTrue(app.menuBars.menuBarItems["Seite"].exists, "Menü von Quill nicht auf Deutsch")
        XCTAssertTrue(app.menuBars.menuBarItems["Bearbeiten"].exists, "Menü von AppKit nicht auf Deutsch")
    }
}
