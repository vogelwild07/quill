import XCTest

/// Text in Bildern (17.1, ADR-034): „Schnell öffnen“ findet ein Bild über seinen Text und
/// springt dorthin. Das Bild mit Schrift erzeugt die App selbst (`-QuillTestImage text`)
/// in ihrer eigenen Zwischenablage; Vision rechnet nur lokal.
@MainActor
final class ImageTextUITests: XCTestCase {
    private var app: XCUIApplication!
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.vogelwild07.quill.uitests.\(UUID().uuidString)"))
    private let image = "\u{FFFC}"

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.quill()
        app.launchArguments += ["-QuillPasteboardName", pasteboard.name.rawValue, "-QuillTestImage", "text"]
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        window.click()
    }

    override func tearDown() async throws {
        app?.terminate()
        pasteboard.releaseGlobally()
    }

    func testSearchFindsTextInImage() throws {
        createPage("Ausflug")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeKey("v", modifierFlags: .command)
        waitFor(self.editor.value as? String == "\(self.image)\n\n", "Bild nicht eingesetzt")
        createPage("Anderes")

        // Erkannt wird im Hintergrund nach dem Speichern: Suche wiederholen, bis das Bild kommt.
        app.typeKey("o", modifierFlags: .command)
        waitForFocus(field)
        let expected = "Ausflug, Bild, Fahrplan Gardasee"
        var found = false
        for _ in 0..<8 where !found {
            app.typeKey("a", modifierFlags: .command)
            app.typeText("gardasee")
            found = XCTWaiter().wait(for: [expectation(for: NSPredicate { _, _ in self.rowLabels == [expected] }, evaluatedWith: nil)], timeout: 3) == .completed
        }
        XCTAssertTrue(found, "Treffer: \(rowLabels) statt \(expected)")

        app.typeKey(.return, modifierFlags: [])
        waitFor(!self.panel.exists, "Schnell öffnen bleibt offen")
        waitFor(self.window.title == "Ausflug", "Nicht zur Seite mit dem Bild gesprungen")
        waitForFocus(editor)
        // Die Einfügemarke steht am Bild: Tippen legt einen Absatz davor an.
        app.typeText("Karte")
        waitFor(self.editor.value as? String == "Karte\n\(self.image)\n\n", "Einfügemarke nicht am Bild: \(editor.value ?? "")")
    }

    // MARK: - Hilfen

    private var window: XCUIElement {
        app.windows.firstMatch
    }

    private var panel: XCUIElement {
        window.descendants(matching: .any)["quickOpen.panel"]
    }

    private var field: XCUIElement {
        window.textFields["quickOpen.field"]
    }

    private var rowLabels: [String] {
        window.descendants(matching: .any).matching(identifier: "quickOpen.row").allElementsBoundByIndex.map(\.label)
    }

    private var editor: XCUIElement {
        window.textViews["editor.text"]
    }

    private var outline: XCUIElement {
        window.outlines["sidebar.pages"]
    }

    private func createPage(_ title: String) {
        let count = outline.pageRows.count
        app.typeKey("n", modifierFlags: .command)
        waitFor(self.outline.pageRows.count == count + 1, "Keine neue Seite")
        let titleField = window.descendants(matching: .any)["detail.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        waitForFocus(titleField)
        app.typeText(title)
    }

    private func waitForFocus(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        waitFor(element.value(forKey: "hasKeyboardFocus") as? Bool == true, "Kein Fokus auf \(element)", file: file, line: line)
    }

    private func waitFor(_ condition: @autoclosure @escaping () -> Bool, _ message: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, message(), file: file, line: line)
    }
}
