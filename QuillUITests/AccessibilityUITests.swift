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

    // MARK: - Hilfen

    private var window: XCUIElement { app.windows.firstMatch }

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
