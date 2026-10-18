import AppKit
import XCTest

/// Bild-Block: Einsetzen aus der Zwischenablage, Undo, Seitenwechsel, Hinweis beim
/// Verkleinern. Bilder werden im Test erzeugt; die App nutzt eine eigene
/// Zwischenablage (`-QuillPasteboardName`), die des Nutzers bleibt unberührt.
/// Ein Bild-Block steht im Text der Bedienungshilfen als U+FFFC.
/// Die Dateiauswahl (Slash-Menü „Bild“) läuft in der Sandbox außerhalb der App und
/// wird von Hand geprüft; hier nur der Eintrag im Menü.
@MainActor
final class ImageBlockUITests: XCTestCase {
    private var app: XCUIApplication!
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("de.vogel.quill.uitests.\(UUID().uuidString)"))
    private let image = "\u{FFFC}"

    // Die async-Varianten laufen auf dem Main Actor wie die XCUITest-APIs;
    // `setUpWithError`/`tearDownWithError` wären nonisolated.
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.quill()
        app.launchArguments += ["-QuillPasteboardName", pasteboard.name.rawValue]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.windows.firstMatch.click()
    }

    override func tearDown() async throws {
        app.terminate()
        pasteboard.releaseGlobally()
    }

    // MARK: - Tests

    func testPastedImageIsUndoableAndSurvivesPageSwitch() throws {
        let generalChangeCount = NSPasteboard.general.changeCount
        createPage("Bilder")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Oben\r")
        putImage(Self.png(width: 120, height: 60))
        app.typeKey("v", modifierFlags: .command)
        assertEditorText("Oben\n\(image)\n\n")

        app.typeKey("z", modifierFlags: .command)
        assertEditorText("Oben\n\n")
        app.typeKey("z", modifierFlags: [.command, .shift])
        assertEditorText("Oben\n\(image)\n\n")

        // Seitenwechsel: gespeichert und mit Bild wieder geladen.
        createPage("Andere")
        row(0).click()
        assertEditorText("Oben\n\(image)\n\n")
        XCTAssertEqual(NSPasteboard.general.changeCount, generalChangeCount, "Allgemeine Zwischenablage wurde verändert")
    }

    func testPastingImageOverSelectionIsOneUndoStep() throws {
        createPage("Auswahl")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("Hallo Welt")
        app.typeKey("a", modifierFlags: .command)
        putImage(Self.png(width: 40, height: 40))
        app.typeKey("v", modifierFlags: .command)
        assertEditorText("\(image)\n\n")

        app.typeKey("z", modifierFlags: .command)
        assertEditorText("Hallo Welt\n")
    }

    func testHeavyImageShowsDownscaleNotice() throws {
        createPage("Groß")
        app.typeText("\r")
        waitForFocus(editor)
        let data = Self.heavyPNG()
        XCTAssertGreaterThan(data.count, 20 * 1024 * 1024)
        putImage(data)
        app.typeKey("v", modifierFlags: .command)
        assertEditorText("\(image)\n\n")

        let notice = app.descendants(matching: .any)["editor.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 20), "Kein Hinweis: \(app.windows.firstMatch.debugDescription)")
        XCTAssertEqual(notice.label, "Bild wurde verkleinert")
    }

    func testSlashMenuOffersImage() throws {
        createPage("Slash")
        app.typeText("\r")
        waitForFocus(editor)
        app.typeText("/bild")
        let entry = app.descendants(matching: .any)["slash.image"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(entry.label, "Bild")
        app.typeKey(.escape, modifierFlags: [])
        assertEditorText("/bild\n")
    }

    // MARK: - Testbilder

    private func putImage(_ png: Data) {
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    static func png(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    }

    /// Rauschen lässt sich kaum komprimieren: ein PNG über 20 MB.
    static func heavyPNG() -> Data {
        let width = 2700, height = 2700
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        arc4random_buf(&bytes, bytes.count)
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    }

    // MARK: - Hilfen (wie in `EditorUITests`)

    private var outline: XCUIElement {
        app.windows.firstMatch.outlines["sidebar.pages"]
    }

    private var editor: XCUIElement {
        app.windows.firstMatch.textViews["editor.text"]
    }

    private var title: XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)["detail.title"]
    }

    private func row(_ index: Int) -> XCUIElement {
        outline.outlineRows.element(boundBy: index)
    }

    private func createPage(_ name: String) {
        let count = outline.outlineRows.count
        app.typeKey("n", modifierFlags: .command)
        let added = NSPredicate { _, _ in self.outline.outlineRows.count == count + 1 }
        wait(for: [expectation(for: added, evaluatedWith: nil)], timeout: 5)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        waitForFocus(title)
        app.typeText(name)
    }

    private func waitForFocus(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let focused = NSPredicate { _, _ in element.value(forKey: "hasKeyboardFocus") as? Bool == true }
        let result = XCTWaiter.wait(for: [expectation(for: focused, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, "Kein Fokus auf \(element)", file: file, line: line)
    }

    private func assertEditorText(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let matches = NSPredicate { _, _ in self.editor.value as? String == expected }
        let result = XCTWaiter.wait(for: [expectation(for: matches, evaluatedWith: nil)], timeout: 10)
        XCTAssertEqual(result, .completed, "Editor: \((editor.value as? String)?.debugDescription ?? "nil") statt \(expected.debugDescription)", file: file, line: line)
    }
}
