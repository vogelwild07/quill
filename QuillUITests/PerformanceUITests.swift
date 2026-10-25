#if QUILL_PROFILING
import XCTest

/// Kaltstart, Sidebar und Seitenwechsel mit 1000 Seiten (`docs/performance.md`).
///
/// Nur im Schema „Quill Profiling“: Die App heißt dort „Quill Profiling“, hat die
/// Bundle-ID `io.github.vogelwild07.quill.profiling` und damit einen eigenen Container und Store.
/// Testargumente für den Store gibt es dort nicht (Package ohne `DEBUG`); den
/// Bestand legt `-QuillSeedPages` einmal vor den Messungen an, nicht mitgemessen.
/// Die Schwellen prüft `Scripts/perf-ui.py` aus dem Ergebnis-Bundle.
@MainActor
final class PerformanceUITests: XCTestCase {
    private static let pages = 1000
    private static var isSeeded = false

    private let subsystem = "io.github.vogelwild07.quill"
    private let category = "PointsOfInterest"

    override func setUp() async throws {
        continueAfterFailure = false
        guard !Self.isSeeded else { return }
        let app = Self.profilingApp(arguments: ["-QuillSeedPages", "\(Self.pages)"])
        app.launch()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 500), "Seed nicht fertig")
        Self.isSeeded = true
    }

    /// Ohne gespeicherten Fensterzustand; Store im Container der Profiling-App.
    private static func profilingApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
            + XCUIApplication.languageArguments(languages: ["de"], region: "DE") + arguments
        return app
    }

    private func signpost(_ name: String) -> XCTOSSignpostMetric {
        XCTOSSignpostMetric(subsystem: subsystem, category: category, name: name)
    }

    private func options(iterations: Int) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        return options
    }

    private func waitForSidebar(_ app: XCUIApplication) {
        XCTAssertTrue(app.outlines["sidebar.pages"].pageRows.firstMatch.waitForExistence(timeout: 30), "Sidebar leer")
    }

    /// Start bis zur gezeichneten Sidebar mit 1000 Seiten: Prozessstart
    /// (`XCTApplicationLaunchMetric`), `launch` und `sidebarLoad`.
    func testColdLaunch() {
        let app = Self.profilingApp()
        app.launch()
        waitForSidebar(app)
        app.terminate()

        measure(
            metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true), signpost("launch"), signpost("sidebarLoad")],
            options: options(iterations: 5)
        ) {
            app.launch()
            waitForSidebar(app)
            app.terminate()
        }
    }

    /// Neue Seite (⌘N) bei 1000 Seiten: Neuladen der Sidebar.
    func testSidebarReload() {
        let app = Self.profilingApp()
        app.launch()
        waitForSidebar(app)
        let rows = app.outlines["sidebar.pages"].pageRows
        app.typeKey("n", modifierFlags: .command)
        app.typeKey(.escape, modifierFlags: [])

        measure(metrics: [signpost("sidebarReload")], options: options(iterations: 5)) {
            let before = rows.count
            app.typeKey("n", modifierFlags: .command)
            XCTAssertTrue(rows.element(boundBy: before).waitForExistence(timeout: 10), "Neue Seite fehlt")
            app.typeKey(.escape, modifierFlags: [])
            settle()
        }
        app.terminate()
    }

    /// Klick auf eine andere Seite bis zum gezeichneten Editor (50 Blöcke, jede
    /// fünfte Wurzel mit Bild): `pageSwitch`.
    func testPageSwitch() {
        let app = Self.profilingApp()
        app.launch()
        waitForSidebar(app)
        let rows = app.outlines["sidebar.pages"].pageRows
        var next = 0
        func open() {
            let row = rows.element(boundBy: next % 10)
            let title = row.textFields["sidebar.page"].value as? String ?? ""
            row.click()
            let editor = app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "\(title), Absatz 0:")).firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 10), "Editor für \(title) fehlt")
            settle()
            next += 1
        }
        open()

        measure(metrics: [signpost("pageSwitch")], options: options(iterations: 10)) {
            open()
        }
        app.terminate()
    }

    /// Kurz warten, damit das Intervall nach dem Zeichnen endet, bevor der Lauf endet.
    private func settle() {
        RunLoop.current.run(until: .now + 0.3)
    }
}
#endif
