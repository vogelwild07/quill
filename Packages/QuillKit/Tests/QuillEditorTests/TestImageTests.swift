#if canImport(AppKit) && DEBUG
import AppKit
@testable import QuillEditor
import Testing

/// Testbild für UI-Tests (`-QuillTestImage`): nur in eine eigene Zwischenablage,
/// nur mit gültiger Angabe.
@MainActor
@Suite("Editor: Testbild für UI-Tests")
struct TestImageTests {
    @Test func putsImageOnOwnPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.vogelwild07.quill.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(TestImage.put(arguments: ["Quill", "-QuillTestImage", "120x60"], on: pasteboard))
        let data = try #require(pasteboard.data(forType: .png))
        let image = try #require(NSBitmapImageRep(data: data))
        #expect(image.pixelsWide == 120 && image.pixelsHigh == 60)
    }

    @Test func neverTouchesGeneralPasteboard() {
        let changeCount = NSPasteboard.general.changeCount
        #expect(!TestImage.put(arguments: ["-QuillTestImage", "10x10"], on: .general))
        #expect(NSPasteboard.general.changeCount == changeCount)
    }

    @Test(arguments: ["", "0x10", "10", "10x10x10", "axb", "5000x10"])
    func rejectsInvalidSpec(_ spec: String) {
        #expect(TestImage.png(spec: spec) == nil)
    }

    /// Bild mit Schrift für die Texterkennung (ADR-034): hell mit dunklen Stellen.
    @Test func textImageHasDarkLettering() throws {
        let data = try #require(TestImage.png(spec: "text"))
        let image = try #require(NSBitmapImageRep(data: data))
        let brightness = (0..<image.pixelsWide).compactMap { image.colorAt(x: $0, y: image.pixelsHigh / 2)?.brightnessComponent }
        #expect(brightness.contains { $0 > 0.9 })
        #expect(brightness.contains { $0 < 0.3 })
    }

    /// Bild für die README: breit wie ein Titelbild, nicht einfarbig.
    @Test func demoImageIsWideLandscape() throws {
        let data = try #require(TestImage.png(spec: "demo"))
        let image = try #require(NSBitmapImageRep(data: data))
        #expect(image.pixelsWide == 1600 && image.pixelsHigh == 640)
        let top = try #require(image.colorAt(x: 10, y: 10))
        let bottom = try #require(image.colorAt(x: 10, y: 630))
        #expect(top != bottom)
    }

    @Test func heavyImageIsOver20MB() throws {
        #expect(try #require(TestImage.png(spec: "heavy")).count > 20 * 1024 * 1024)
    }
}
#endif
