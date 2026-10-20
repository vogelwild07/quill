#if canImport(AppKit)
import AppKit
import ImageIO
import QuillModel
import Testing
@testable import QuillEditor
import QuillTestFixtures

/// Rendert den Editor hell und dunkel aus der App selbst (keine Bildschirmfotos)
/// und prüft, dass selbst gezeichnete Elemente Systemfarben nutzen.
/// Die PNGs landen in `$TMPDIR/QuillEditorSnapshots` zur Sichtkontrolle; ersetzt
/// `-snapshot` des gelöschten Editor-Spikes.
@MainActor
@Suite("Editor: Darstellung hell und dunkel", .serialized, .renderingLock)
struct EditorSnapshotTests {
    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func editorUsesSystemColors(_ appearance: NSAppearance.Name) throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let editor = BlockEditorController(document: SampleDocuments.welcome)
        window.contentView = editor.scrollView
        editor.textView.layoutSubtreeIfNeeded()
        let firstLine = editor.textView.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
        let point = editor.textView.convert(window.convertPoint(fromScreen: firstLine.origin), from: nil)
        editor.textView.updateHandle(for: CGPoint(x: 100, y: point.y - 4))
        #expect(!editor.textView.handle.isHidden)
        #expect(!editor.textView.insertButton.isHidden)

        let view = try #require(window.contentView)
        let image = try Bitmap(view)
        try image.writePNG(named: "editor-\(appearance.rawValue)")

        let background = image.luminance(atX: image.width - 4, y: image.height - 4)
        if appearance == .darkAqua {
            // Fest schwarz gezeichnete Elemente wären dunkler als der Hintergrund.
            #expect(image.minimumLuminance >= background - 0.02)
        } else {
            #expect(image.maximumLuminance <= background + 0.02)
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func handleUsesTertiaryAndOnHoverSecondaryLabel(_ appearance: NSAppearance.Name) throws {
        let handle = BlockHandleView(frame: CGRect(x: 0, y: 0, width: 20, height: 22))
        handle.appearance = NSAppearance(named: appearance)

        let normal = try Bitmap(handle)
        handle.isHovered = true
        let hovered = try Bitmap(handle)
        try hovered.writePNG(named: "handle-hover-\(appearance.rawValue)")

        let dark = appearance == .darkAqua
        // Punkte erscheinen hell auf dunkel bzw. dunkel auf hell …
        #expect(dark ? normal.strongestDot.brightness > 0.8 : normal.strongestDot.brightness < 0.2)
        // … und bei Hover deckender.
        #expect(hovered.strongestDot.alpha > normal.strongestDot.alpha + 0.1)
        // Sechs Punkte (⋮⋮), nicht drei Striche (≡).
        #expect(normal.dotCount == 6)
    }
}

@MainActor
@Suite("Editor: Inline-Code zeichnen", .serialized, .renderingLock)
struct InlineCodeSnapshotTests {
    @MainActor
    private struct Rendered {
        let window: NSWindow
        let editor: BlockEditorController
        let bitmap: Bitmap

        /// Fragmente in Dokumentreihenfolge.
        var fragments: [BlockLayoutFragment] {
            var result: [BlockLayoutFragment] = []
            editor.textView.textLayoutManager?.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
                if let fragment = fragment as? BlockLayoutFragment { result.append(fragment) }
                return true
            }
            return result
        }

        /// Pixelzeilen (y nach unten) eines Fragments im Bild.
        func pixelRows(of fragment: NSTextLayoutFragment) throws -> Range<Int> {
            let content = try #require(window.contentView)
            let rect = content.convert(editor.textView.viewFrame(of: fragment), from: editor.textView)
            let scale = Double(bitmap.width) / content.bounds.width
            let top = content.isFlipped ? rect.minY : content.bounds.height - rect.maxY
            return Int((top * scale).rounded(.down))..<Int(((top + rect.height) * scale).rounded(.up))
        }
    }

    private func render(_ document: EditorDocument, appearance: NSAppearance.Name) throws -> Rendered {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let editor = BlockEditorController(document: document)
        window.contentView = editor.scrollView
        editor.textView.layoutSubtreeIfNeeded()
        return Rendered(window: window, editor: editor, bitmap: try Bitmap(try #require(window.contentView)))
    }

    /// Bekanntes Problem aus der Roadmap: Der Hintergrund reichte einmal in die Zeile
    /// darüber. Der Absatz darüber muss mit und ohne Inline-Code pixelgleich sein.
    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func backgroundStaysInItsLine(_ appearance: NSAppearance.Name) throws {
        let with = try render(SampleDocuments.inlineCode(), appearance: appearance)
        let without = try render(SampleDocuments.inlineCode(withCode: false), appearance: appearance)
        try with.bitmap.writePNG(named: "inline-code-\(appearance.rawValue)")

        let fragments = with.fragments
        try #require(fragments.count >= 4)
        #expect(fragments[0].textLineFragments.count == 2, "Absatz darüber soll umbrechen")
        let above = try with.pixelRows(of: fragments[0])
        #expect(with.bitmap.rowsEqual(without.bitmap, above), "Hintergrund reicht in den Absatz darüber")
        // Sichtprobe: Mit Inline-Code ist im Absatz selbst etwas unterlegt.
        #expect(!with.bitmap.rowsEqual(without.bitmap, try with.pixelRows(of: fragments[1])))

        // Jedes Rechteck liegt in seiner Zeile.
        for fragment in fragments[1...2] {
            let rects = fragment.inlineCodeRects
            #expect(!rects.isEmpty)
            for rect in rects {
                let line = try #require(fragment.textLineFragments.first { $0.typographicBounds.intersects(rect) })
                #expect(rect.minY >= line.typographicBounds.minY - 0.5)
                #expect(rect.maxY <= line.typographicBounds.maxY + 0.5)
            }
        }
        // Umbrochener Inline-Code: ein Rechteck je Zeile, übereinander ohne Überlappung.
        let wrapped = fragments[2].inlineCodeRects
        #expect(wrapped.count == 2)
        if wrapped.count == 2 { #expect(wrapped[0].maxY <= wrapped[1].minY) }
    }

    /// Ein weicher Umbruch am Ende des Inline-Codes wird nicht mit unterlegt.
    @Test func trailingSoftBreakIsNotUnderlaid() throws {
        let marked = try render(SampleDocuments.inlineCodeBeforeSoftBreak(markingBreak: true), appearance: .aqua)
        let plain = try render(SampleDocuments.inlineCodeBeforeSoftBreak(markingBreak: false), appearance: .aqua)
        let rects = try #require(marked.fragments.first).inlineCodeRects
        #expect(rects.count == 1)
        #expect(rects == (try #require(plain.fragments.first).inlineCodeRects))
    }
}

@MainActor
@Suite("Editor: Bild-Block zeichnen", .serialized, .renderingLock)
struct ImageBlockSnapshotTests {
    /// Einfarbiges Testbild, im Test erzeugt.
    static func solidImage(width: Int, height: Int, red: CGFloat = 0.9, green: CGFloat = 0.1, blue: CGFloat = 0.1) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func render(_ document: EditorDocument, appearance: NSAppearance.Name) throws -> Bitmap {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let editor = BlockEditorController(document: document)
        window.contentView = editor.scrollView
        editor.textView.layoutSubtreeIfNeeded()
        return try Bitmap(try #require(window.contentView))
    }

    /// Prüftest für ADR-015 (Darstellung A): Das Fragment zeichnet das Bild an der
    /// Stelle, die das Attachment reserviert, skaliert auf die Textbreite.
    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func fragmentDrawsScaledImageBetweenParagraphs(_ appearance: NSAppearance.Name) throws {
        let id = UUID()
        let image = Self.solidImage(width: 1200, height: 600)
        EditorImageCache.shared.store(.init(pointSize: CGSize(width: 1200, height: 600), image: image), for: id)
        let document = EditorDocument(blocks: [
            EditorBlock(text: "Oben"),
            EditorBlock(kind: .image, properties: BlockProperties(assetID: id)),
            EditorBlock(text: "Unten"),
        ])
        let bitmap = try render(document, appearance: appearance)
        try bitmap.writePNG(named: "image-block-\(appearance.rawValue)")

        let red = try #require(bitmap.boundingBox { $0.r > 0.75 && $0.g < 0.3 && $0.b < 0.3 && $0.a > 0.9 })
        // Breiter als die Textspalte: auf die Breite skaliert, Seitenverhältnis 2 : 1.
        let points = Double(red.width) / (Double(bitmap.width) / 640)
        #expect(points > 400 && points < 640)
        #expect(abs(Double(red.width) / Double(red.height) - 2) < 0.05)

        // Text („Oben“, „Unten“) über und unter dem Bild, nicht darin.
        let dark = appearance == .darkAqua
        let textRows = bitmap.rows { pixel in
            let gray = max(pixel.r, pixel.g, pixel.b) - min(pixel.r, pixel.g, pixel.b) < 0.1
            return pixel.a > 0.5 && gray && (dark ? pixel.g > 0.6 : pixel.g < 0.4)
        }
        #expect(textRows.contains { $0 < red.minY })
        #expect(textRows.contains { $0 > red.maxY })
        #expect(!textRows.contains { $0 > red.minY + 2 && $0 < red.maxY - 2 })
    }

    @Test func smallImagesKeepTheirSize() throws {
        let id = UUID()
        EditorImageCache.shared.store(.init(pointSize: CGSize(width: 80, height: 40), image: Self.solidImage(width: 80, height: 40)), for: id)
        let bitmap = try render(EditorDocument(blocks: [EditorBlock(kind: .image, properties: BlockProperties(assetID: id)), EditorBlock()]), appearance: .aqua)
        let red = try #require(bitmap.boundingBox { $0.r > 0.75 && $0.g < 0.3 && $0.b < 0.3 && $0.a > 0.9 })
        // Bitmap in Pixeln, Fenster in Punkten: Faktor der Bildschirmauflösung.
        let scale = Double(bitmap.width) / 640
        #expect(abs(Double(red.width) / scale - 80) <= 2)
        #expect(abs(Double(red.height) / scale - 40) <= 2)
    }

    @Test func retinaImagesAppearInScreenSize() throws {
        let id = UUID()
        // 160 × 80 Pixel bei 144 DPI wie ein Retina-Bildschirmfoto: 80 × 40 Punkte.
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, Self.solidImage(width: 160, height: 80), [
            kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144,
        ] as CFDictionary)
        CGImageDestinationFinalize(destination)
        EditorImageCache.shared.store(try #require(EditorImageCache.decode(output as Data)), for: id)

        let bitmap = try render(EditorDocument(blocks: [EditorBlock(kind: .image, properties: BlockProperties(assetID: id)), EditorBlock()]), appearance: .aqua)
        let red = try #require(bitmap.boundingBox { $0.r > 0.75 && $0.g < 0.3 && $0.b < 0.3 && $0.a > 0.9 })
        let scale = Double(bitmap.width) / 640
        #expect(abs(Double(red.width) / scale - 80) <= 2)
        #expect(abs(Double(red.height) / scale - 40) <= 2)
    }

    @Test func missingImageShowsPlaceholderNotRed() throws {
        let bitmap = try render(EditorDocument(blocks: [EditorBlock(kind: .image, properties: BlockProperties(assetID: UUID())), EditorBlock()]), appearance: .aqua)
        #expect(bitmap.boundingBox { $0.r > 0.75 && $0.g < 0.3 && $0.b < 0.3 && $0.a > 0.9 } == nil)
    }
}
#endif
