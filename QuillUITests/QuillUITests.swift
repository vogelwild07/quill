import AppKit
import XCTest

@MainActor
final class QuillUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsMainWindow() throws {
        let app = XCUIApplication.quill()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    /// Alle Fenster auf dem Hauptbildschirm (`-QuillWindowsOnMainScreen`), auch mit
    /// zweitem Monitor: Hauptfenster und Einstellungen.
    func testWindowsLieOnTheMainScreen() throws {
        let app = XCUIApplication.quill()
        app.launch()
        let main = app.windows.firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 5))
        // Koordinaten von XCUITest: Ursprung oben links auf dem Hauptbildschirm.
        let screen = CGRect(origin: .zero, size: try XCTUnwrap(NSScreen.screens.first).frame.size)
        XCTAssertTrue(screen.contains(main.frame), "Hauptfenster \(main.frame) nicht in \(screen)")
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.containing(.any, identifier: "settings.focusMode").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Einstellungen nicht geöffnet")
        XCTAssertTrue(screen.contains(settings.frame), "Einstellungen \(settings.frame) nicht in \(screen)")
    }
}
