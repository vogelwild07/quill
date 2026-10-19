#if canImport(AppKit)
import AppKit
import Testing
@testable import QuillEditor

/// Hinweis auf einer leeren Seite (Phase 7.3): nur gezeichnet, nie im Text oder
/// Modell, weg beim ersten Zeichen, für VoiceOver ein Platzhalter. Dass er nicht
/// exportiert wird, prüft `EmptyPageExportTests`.
@MainActor
@Suite("Editor: Hinweis auf leerer Seite", .serialized)
struct EmptyPageHintTests {
    private let window: NSWindow
    private let editor: BlockEditorController
    private var textView: BlockTextView { editor.textView }

    init() {
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        editor = BlockEditorController(document: EditorDocument())
        window.contentView = editor.scrollView
        editor.focus()
        textView.layoutSubtreeIfNeeded()
    }

    @Test func emptyPageShowsHintOnlyAsDrawing() throws {
        #expect(textView.showsEmptyPageHint)
        #expect(textView.accessibilityPlaceholderValue() == BlockTextView.emptyPageHint)
        #expect(textView.string == "\n")
        #expect(editor.document.blocks.map(\.text) == [""])
        #expect(!textView.attributedString().string.contains(BlockTextView.emptyPageHint))
    }

    @Test func firstCharacterHidesHint() {
        textView.insertText("a", replacementRange: textView.selectedRange())
        #expect(!textView.showsEmptyPageHint)
        #expect(!textView.isShowingEmptyPageHint)
        #expect(textView.accessibilityPlaceholderValue() == nil)
        // Wieder leer: Der Hinweis kommt zurück.
        textView.deleteBackward(nil)
        #expect(textView.showsEmptyPageHint)
        #expect(textView.isShowingEmptyPageHint)
    }

    /// Markierter Text (IME, tote Tasten) blendet den Hinweis aus, bevor ein Zeichen feststeht.
    @Test func markedTextHidesHint() {
        textView.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(textView.hasMarkedText())
        #expect(!textView.showsEmptyPageHint)
        #expect(!textView.isShowingEmptyPageHint)
    }

    @Test func onlyEmptyTextParagraphShowsHint() {
        editor.load(EditorDocument(blocks: [EditorBlock(kind: .heading1)]))
        #expect(!textView.showsEmptyPageHint)
        editor.load(EditorDocument(blocks: [EditorBlock(), EditorBlock()]))
        #expect(!textView.showsEmptyPageHint)
        editor.load(EditorDocument())
        #expect(textView.showsEmptyPageHint)
    }

    @Test func copyingEmptyPageNeverCopiesHint() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.vogelwild07.quill.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        textView.selectAll(nil)
        _ = editor.copySelection(to: pasteboard)
        for type in pasteboard.types ?? [] {
            let text = pasteboard.string(forType: type) ?? String(data: pasteboard.data(forType: type) ?? Data(), encoding: .utf8) ?? ""
            #expect(!text.contains(BlockTextView.emptyPageHint), "\(type.rawValue)")
        }
    }

    /// Hell und dunkel: Der Hinweis ist in der ersten Zeile zu sehen, in der Farbe
    /// für Platzhalter (zwischen Text und Hintergrund), und verschwindet beim Tippen.
    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func hintIsDrawnInPlaceholderColor(_ appearance: NSAppearance.Name) throws {
        window.appearance = NSAppearance(named: appearance)
        textView.layoutSubtreeIfNeeded()
        let rect = try #require(textView.emptyPageHintRect)
        #expect(rect.width > 200 && rect.height > 10)
        try writePNG(named: "empty-page-hint-\(appearance.rawValue)")
        let shown = try inkRange(in: rect)
        #expect(shown.count > 50, "Kein Hinweis gezeichnet")
        // Platzhalterfarbe: deutlich schwächer als Text in voller Deckung.
        let background = try backgroundBrightness()
        let strongest = shown.map { abs($0 - background) }.max() ?? 0
        #expect(strongest > 0.2 && strongest < 0.75, "Kontrast \(strongest) passt nicht zu placeholderTextColor")

        textView.insertText("a", replacementRange: textView.selectedRange())
        // Rechts vom getippten „a“.
        let hidden = try inkRange(in: rect.offsetBy(dx: 30, dy: 0))
        #expect(hidden.isEmpty, "Hinweis nach dem Tippen noch sichtbar")
    }

    // MARK: - Pixel

    /// Zur Sichtkontrolle nach `$TMPDIR/QuillEditorSnapshots`.
    private func writePNG(named name: String) throws {
        let (rep, _) = try bitmap()
        let directory = FileManager.default.temporaryDirectory.appending(path: "QuillEditorSnapshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #require(rep.representation(using: .png, properties: [:])).write(to: directory.appending(path: "\(name).png"))
    }

    private func bitmap() throws -> (rep: NSBitmapImageRep, view: NSView) {
        let view = try #require(window.contentView)
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return (rep, view)
    }

    private func brightness(_ color: NSColor) -> Double {
        let c = color.usingColorSpace(.sRGB) ?? color
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }

    private func backgroundBrightness() throws -> Double {
        let (rep, _) = try bitmap()
        return brightness(try #require(rep.colorAt(x: rep.pixelsWide - 3, y: rep.pixelsHigh - 3)))
    }

    /// Helligkeiten der Pixel im Rechteck, die sich vom Hintergrund abheben.
    private func inkRange(in rect: CGRect) throws -> [Double] {
        let (rep, view) = try bitmap()
        let background = brightness(try #require(rep.colorAt(x: rep.pixelsWide - 3, y: rep.pixelsHigh - 3)))
        let inView = textView.convert(rect, to: view)
        let scale = Double(rep.pixelsWide) / view.bounds.width
        var result: [Double] = []
        for y in Int(inView.minY * scale)..<Int(inView.maxY * scale) {
            for x in Int(inView.minX * scale)..<Int(inView.maxX * scale) {
                // Bitmap-Zeilen von oben; `view` ist nicht gespiegelt.
                let row = view.isFlipped ? y : rep.pixelsHigh - 1 - y
                guard x >= 0, row >= 0, x < rep.pixelsWide, row < rep.pixelsHigh,
                      let color = rep.colorAt(x: x, y: row) else { continue }
                let value = brightness(color)
                if abs(value - background) > 0.08 { result.append(value) }
            }
        }
        return result
    }
}
#endif
