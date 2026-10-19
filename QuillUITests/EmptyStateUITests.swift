import XCTest

/// Leerzustände beim ersten Start: Sidebar ohne Seiten, Detail ohne Auswahl mit
/// Knopf „Neue Seite“ (Phase 7.3). Darstellung hell/dunkel prüft
/// `EmptyStateSnapshotTests` im Package.
@MainActor
final class EmptyStateUITests: XCTestCase {
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

    /// Hinweis auf leerer Seite: für VoiceOver ein Platzhalter, weg beim ersten Zeichen.
    func testEmptyPageHintIsPlaceholder() throws {
        let window = app.windows.firstMatch
        app.typeKey("n", modifierFlags: .command)
        let title = window.descendants(matching: .any)["detail.title"]
        let titleFocused = NSPredicate { _, _ in title.value(forKey: "hasKeyboardFocus") as? Bool == true }
        wait(for: [expectation(for: titleFocused, evaluatedWith: nil)], timeout: 5)
        app.typeText("Leer\r")
        let editor = window.textViews["editor.text"]
        XCTAssertEqual(editor.placeholderValue, "Leere Seite – mit „/“ wählst du eine Blockart.")
        XCTAssertEqual(editor.value as? String, "\n", "Hinweis steht im Text")
        app.typeText("x")
        let gone = NSPredicate { _, _ in (editor.placeholderValue ?? "").isEmpty }
        wait(for: [expectation(for: gone, evaluatedWith: nil)], timeout: 5)
    }

    func testFirstLaunchShowsEmptyStatesAndCreatesFirstPage() throws {
        let window = app.windows.firstMatch
        let sidebarEmpty = window.staticTexts["sidebar.emptyState.title"]
        XCTAssertTrue(sidebarEmpty.waitForExistence(timeout: 5), "Kein Leerzustand in der Sidebar")
        XCTAssertEqual(sidebarEmpty.value as? String, "Noch keine Seiten")
        XCTAssertFalse(window.outlines["sidebar.pages"].exists)

        let detailEmpty = window.staticTexts["detail.emptyState.title"]
        XCTAssertTrue(detailEmpty.exists, "Kein Leerzustand im Detailbereich")
        XCTAssertEqual(detailEmpty.value as? String, "Keine Seite ausgewählt")
        let create = window.buttons["detail.emptyState.action"]
        XCTAssertTrue(create.exists, "Kein Knopf im Leerzustand")
        XCTAssertEqual(create.label, "Neue Seite")
        create.click()

        let outline = window.outlines["sidebar.pages"]
        XCTAssertTrue(outline.waitForExistence(timeout: 5), "Seitenbaum fehlt nach der ersten Seite")
        XCTAssertEqual(outline.pageRows.count, 1)
        XCTAssertFalse(sidebarEmpty.exists)
        let title = window.descendants(matching: .any)["detail.title"]
        let focused = NSPredicate { _, _ in title.value(forKey: "hasKeyboardFocus") as? Bool == true }
        wait(for: [expectation(for: focused, evaluatedWith: nil)], timeout: 5)
    }
}
