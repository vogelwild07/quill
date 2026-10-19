import AppKit
import XCTest

/// Bilder für die README (`docs/images/`), hell und dunkel: Die App startet mit
/// einem Store nur im Arbeitsspeicher, der Test tippt Demo-Inhalte und nimmt das
/// Fenster per `XCUIElement.screenshot()` auf. Keine echten Daten; das Bild im
/// Text erzeugt die App selbst (`-QuillTestImage demo`), die Fenstergröße setzt sie
/// ebenfalls selbst (`-QuillWindowSize`).
///
/// Läuft nur über `Scripts/readme-screenshots.sh`, sonst übersprungen: Die
/// Aufnahme liest Bildschirmpixel, und Liquid Glass zeigt, was hinter dem Fenster
/// liegt. Das Skript setzt `TEST_RUNNER_QUILL_README_SCREENSHOTS=1`; xcodebuild
/// gibt die Variable ohne Präfix an den Test weiter.
@MainActor
final class ReadmeScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.vogelwild07.quill.uitests.\(UUID().uuidString)"))
    /// Fenstergröße der Bilder in Punkten.
    private let windowSize = CGSize(width: 1180, height: 760)

    // Die async-Varianten laufen auf dem Main Actor wie die XCUITest-APIs;
    // `setUpWithError`/`tearDownWithError` wären nonisolated.
    override func setUp() async throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["QUILL_README_SCREENSHOTS"] == "1",
            "Nur über Scripts/readme-screenshots.sh"
        )
    }

    override func tearDown() async throws {
        app?.terminate()
        pasteboard.releaseGlobally()
    }

    func testLight() throws {
        try capture(appearance: ["-NSRequiresAquaSystemAppearance", "YES"], name: "quill-hell")
    }

    func testDark() throws {
        try capture(appearance: ["-AppleInterfaceStyle", "Dark"], name: "quill-dunkel")
    }

    // MARK: - Ablauf

    /// `appearance` erzwingt das Erscheinungsbild unabhängig vom System:
    /// `-AppleInterfaceStyle Dark` für dunkel, `-NSRequiresAquaSystemAppearance YES`
    /// für hell (`-AppleInterfaceStyle Light` setzt sich gegen ein dunkles System
    /// nicht durch).
    private func capture(appearance: [String], name: String) throws {
        app = XCUIApplication.quill()
        app.launchArguments += appearance + [
            "-QuillPasteboardName", pasteboard.name.rawValue,
            "-QuillTestImage", "demo",
            "-QuillWindowSize", "\(Int(windowSize.width))x\(Int(windowSize.height))",
        ]
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        waitForWindowSize(window)
        window.click()

        writeDemoContent()

        // Ausgangslage fürs Bild: erste Seite gewählt, Fokus in der Sidebar, damit
        // keine Einfügemarke blinkt; das Bild im Text ist geladen.
        row("Willkommen bei Quill").click()
        assertEditorContainsImage()
        settle()

        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func writeDemoContent() {
        createPage("Willkommen bei Quill")
        editText(
            "Notizen, Listen und Pläne an einem Ort, gespeichert nur auf deinem Mac.\r"
                + "## Heute\r"
        )
        todos([("Erste Seite anlegen", true), ("Unterseiten für Projekte", true), ("Ein Bild einsetzen", false)])
        app.typeKey("v", modifierFlags: .command)
        app.typeText("> Absatz für Absatz: Jeder Block lässt sich ziehen, umwandeln und verschieben.")

        createPage("Projekte")
        editText("Was gerade läuft und was als Nächstes kommt.")
        createPage("Umzug planen", subpage: true)
        editText("")
        todos([("Kartons besorgen", true), ("Nachsendeauftrag stellen", false), ("Schlüsselübergabe am Freitag", false)])
        row("Projekte").click()
        createPage("Wochenende in Lissabon", subpage: true)
        editText("## Ideen\r- Tram 28 bis zur Endstation\r- Pastéis in Belém\r- Sonnenuntergang am Miradouro")

        createPage("Leseliste")
        editText("- Ein Roman für den Zug\r- Etwas über Typografie\r- Das Kochbuch vom Flohmarkt")
    }

    // MARK: - Hilfen

    private var outline: XCUIElement {
        app.windows.firstMatch.outlines["sidebar.pages"]
    }

    private var editor: XCUIElement {
        app.windows.firstMatch.textViews["editor.text"]
    }

    private var title: XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)["detail.title"]
    }

    private func row(_ name: String) -> XCUIElement {
        outline.pageRows.containing(NSPredicate(format: "value == %@", name)).firstMatch
    }

    /// Wartet, bis die App das Fenster auf `windowSize` gebracht hat
    /// (`-QuillWindowSize`).
    private func waitForWindowSize(_ window: XCUIElement) {
        let sized = NSPredicate { _, _ in window.frame.size == self.windowSize }
        let result = XCTWaiter.wait(for: [expectation(for: sized, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, "Fenster \(window.frame.size) statt \(windowSize)")
    }

    private func createPage(_ name: String, subpage: Bool = false) {
        let count = outline.pageRows.count
        app.typeKey("n", modifierFlags: subpage ? [.command, .shift] : .command)
        let added = NSPredicate { _, _ in self.outline.pageRows.count == count + 1 }
        wait(for: [expectation(for: added, evaluatedWith: nil)], timeout: 5)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        waitForFocus(title)
        app.typeText(name)
        XCTAssertTrue(row(name).waitForExistence(timeout: 5), "Seite „\(name)“ fehlt in der Sidebar")
    }

    /// Vom Titel in den Text wechseln und `text` tippen.
    private func editText(_ text: String) {
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText(text)
    }

    /// To-dos ab einem leeren Absatz, erledigte per ⌘↩ abgehakt; danach wieder ein
    /// leerer Absatz.
    private func todos(_ items: [(String, done: Bool)]) {
        app.typeText("[] ")
        for (text, done) in items {
            app.typeText(text)
            if done { app.typeKey(.return, modifierFlags: .command) }
            app.typeText("\r")
        }
        app.typeText("\r")
    }

    private func waitForFocus(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let focused = NSPredicate { _, _ in element.value(forKey: "hasKeyboardFocus") as? Bool == true }
        let result = XCTWaiter.wait(for: [expectation(for: focused, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, "Kein Fokus auf \(element)", file: file, line: line)
    }

    /// Ein Bild-Block steht im Text der Bedienungshilfen als U+FFFC.
    private func assertEditorContainsImage(file: StaticString = #filePath, line: UInt = #line) {
        let shown = NSPredicate { _, _ in (self.editor.value as? String)?.contains("\u{FFFC}") == true }
        let result = XCTWaiter.wait(for: [expectation(for: shown, evaluatedWith: nil)], timeout: 10)
        XCTAssertEqual(result, .completed, "Kein Bild im Text: \((editor.value as? String)?.debugDescription ?? "nil")", file: file, line: line)
    }

    /// Kurz warten, bis Bild und Animationen (Auswahl, Glas) fertig gezeichnet sind.
    private func settle() {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Darstellung")], timeout: 1.5)
    }
}
