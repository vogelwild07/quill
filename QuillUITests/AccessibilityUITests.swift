import XCTest

/// Gezielte Prüfungen der Bedienungshilfen (Befunde aus dem Audit in Phase 7.3).
/// Den Audit über alle Ansichten macht `AccessibilityAuditUITests`.
@MainActor
final class AccessibilityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.quill()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.windows.firstMatch.click()
    }

    override func tearDown() async throws {
        app.terminate()
    }

    /// Seitenkopf (A3): beschriftete Gruppe, Symbol und Titel mit Beschriftung.
    func testPageHeaderIsDescribed() throws {
        createPage("Kopf")
        let header = window.textViews["editor.text"].groups["Seitenkopf"]
        XCTAssertTrue(header.waitForExistence(timeout: 5), "Keine Gruppe „Seitenkopf“")
        let icon = header.textFields["detail.icon"]
        XCTAssertEqual(icon.label, "Seitensymbol")
        XCTAssertEqual(icon.value as? String, "Kein Symbol")
        XCTAssertEqual(header.textFields["detail.title"].label, "Seitentitel")
    }

    /// Sidebar-Zeile (A9): Das Standardsymbol ist Schmuck, kein Bild für VoiceOver.
    func testSidebarRowSymbolIsHidden() throws {
        createPage("Ohne Symbol")
        let row = window.outlines["sidebar.pages"].pageRows.element(boundBy: 0)
        XCTAssertTrue(row.textFields["sidebar.page"].waitForExistence(timeout: 5))
        XCTAssertEqual(row.images.count, 0, "Symbol als Bild sichtbar")
    }

    /// Listen beschriftet (A5): Sidebar und Papierkorb.
    func testListsAreLabeled() throws {
        createPage("Weg")
        let sidebar = window.outlines["sidebar.pages"]
        XCTAssertEqual(sidebar.label, "Seiten")
        sidebar.pageRows.element(boundBy: 0).click()
        app.typeKey(.delete, modifierFlags: .command)
        window.descendants(matching: .any)["sidebar.trash"].click()
        let trash = window.outlines["trash.list"]
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        XCTAssertEqual(trash.label, "Seiten im Papierkorb")
    }

    /// „Schnell öffnen“ (A6): beschriftetes Panel, Fokus im Suchfeld.
    func testQuickOpenPanelIsLabeled() throws {
        app.typeKey("o", modifierFlags: .command)
        let panel = window.groups["quickOpen.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertEqual(panel.label, "Schnell öffnen")
        expectFocus(on: panel.textFields["quickOpen.field"], "Suchfeld fokussiert")
    }

    /// Slash-Menü (A7): Panel und Hülle beschriftet.
    func testSlashMenuIsLabeled() throws {
        createPage("Slash")
        app.typeText("\r/")
        let menu = app.descendants(matching: .any)["slash.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let dialog = app.dialogs["Block einfügen"]
        XCTAssertTrue(dialog.exists, "Panel ohne Beschriftung")
        XCTAssertEqual(dialog.children(matching: .group).firstMatch.label, "Block einfügen")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Tastaturfokus (A4): Sidebar →Tab→ Titel →Tab→ Editor →⌃Tab→ Sidebar,
    /// rückwärts mit ⇧; ⇧Tab im Titel → Symbol. Tab im Editor rückt weiter ein.
    func testKeyboardFocusLoop() throws {
        createPage("Fokus")
        app.typeText("\rText")
        let sidebar = window.outlines["sidebar.pages"]
        let title = window.descendants(matching: .any)["detail.title"]
        let icon = window.descendants(matching: .any)["detail.icon"]
        let editor = window.textViews["editor.text"]

        sidebar.pageRows.element(boundBy: 0).click()
        expectFocus(on: sidebar, "Sidebar nach Klick")
        app.typeKey(.tab, modifierFlags: [])
        expectFocus(on: title, "Sidebar →Tab→ Titel")
        app.typeKey(.tab, modifierFlags: [])
        expectFocus(on: editor, "Titel →Tab→ Editor")
        app.typeKey(.tab, modifierFlags: .control)
        expectFocus(on: sidebar, "Editor →⌃Tab→ Sidebar")
        app.typeKey(.tab, modifierFlags: .shift)
        expectFocus(on: editor, "Sidebar →⇧Tab→ Editor")
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        expectFocus(on: title, "Editor →⇧⌃Tab→ Titel")
        app.typeKey(.tab, modifierFlags: .shift)
        expectFocus(on: icon, "Titel →⇧Tab→ Symbol")
        app.typeKey(.tab, modifierFlags: [])
        expectFocus(on: title, "Symbol →Tab→ Titel")
        app.typeKey(.tab, modifierFlags: .shift)
        app.typeKey(.tab, modifierFlags: .shift)
        expectFocus(on: sidebar, "Symbol →⇧Tab→ Sidebar")
        XCTAssertEqual(title.value as? String, "Fokus", "Tab hat den Titel verändert")
    }

    // MARK: - Hilfen

    private var window: XCUIElement { app.windows.firstMatch }

    private func expectFocus(on element: XCUIElement, _ step: String) {
        let focused = NSPredicate { _, _ in element.value(forKey: "hasKeyboardFocus") as? Bool == true }
        let result = XCTWaiter().wait(for: [expectation(for: focused, evaluatedWith: nil)], timeout: 3)
        XCTAssertEqual(result, .completed, step)
    }

    /// ⌘N, dann Titel tippen (der Fokus liegt danach im Titelfeld).
    private func createPage(_ name: String) {
        let outline = window.outlines["sidebar.pages"]
        let count = outline.pageRows.count
        app.typeKey("n", modifierFlags: .command)
        let added = NSPredicate { _, _ in outline.pageRows.count == count + 1 }
        wait(for: [expectation(for: added, evaluatedWith: nil)], timeout: 5)
        let title = window.descendants(matching: .any)["detail.title"]
        let focused = NSPredicate { _, _ in title.value(forKey: "hasKeyboardFocus") as? Bool == true }
        wait(for: [expectation(for: focused, evaluatedWith: nil)], timeout: 5)
        app.typeText(name)
    }
}
