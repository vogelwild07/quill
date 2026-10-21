#if canImport(AppKit) && DEBUG
import Foundation
import Testing
@testable import QuillFeatures

/// Fenster der UI-Tests auf dem Hauptbildschirm (`-QuillWindowsOnMainScreen YES`).
@MainActor
@Suite struct TestWindowScreenTests {
    let main = NSRect(x: 0, y: 0, width: 1512, height: 944)

    @Test func readsFlagFromArguments() {
        #expect(TestWindowScreen.isRequested(arguments: ["Quill", "-QuillWindowsOnMainScreen", "YES"]))
        #expect(!TestWindowScreen.isRequested(arguments: ["Quill"]))
        #expect(!TestWindowScreen.isRequested(arguments: ["Quill", "-QuillWindowsOnMainScreen"]))
        #expect(!TestWindowScreen.isRequested(arguments: ["Quill", "-QuillWindowsOnMainScreen", "NO"]))
    }

    @Test func windowOnTheMainScreenStays() {
        #expect(TestWindowScreen.frame(NSRect(x: 100, y: 100, width: 900, height: 600), on: main) == nil)
    }

    /// Zweiter Monitor rechts oder links vom Hauptbildschirm, auch halb darauf.
    @Test(arguments: [
        NSRect(x: 1800, y: 200, width: 900, height: 600),
        NSRect(x: -1200, y: -100, width: 900, height: 600),
        NSRect(x: 1200, y: 100, width: 900, height: 600),
    ])
    func windowElsewhereMovesToTheMiddleOfTheMainScreen(_ frame: NSRect) throws {
        let moved = try #require(TestWindowScreen.frame(frame, on: main))
        #expect(main.contains(moved))
        #expect(moved.size == frame.size)
        #expect(moved.midX == main.midX && moved.midY == main.midY)
    }

    @Test func tooLargeWindowShrinksToTheMainScreen() throws {
        let moved = try #require(TestWindowScreen.frame(NSRect(x: 1600, y: 0, width: 2560, height: 1400), on: main))
        #expect(moved == main)
    }
}
#endif
