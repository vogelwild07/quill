#if canImport(AppKit)
import AppKit
@testable import QuillEditor
@testable import QuillEditorCore
import QuillTestFixtures
import Testing

/// Platzhalter, Ziehgriff, Plus-Knopf und Trennlinie in den Farben des Themes (ADR-024),
/// gezeichnet und gemessen in jedem Theme bei hellem und dunklem System, feste Themes
/// also auch gegen das System: Platzhalter 4,5 : 1, Bedienelemente und Linie 3 : 1.
/// „Kontrast erhöhen“ lässt sich im Test nicht einschalten; das prüft `EditorThemeContrastTests`.
@MainActor
@Suite("Theme: Bedienelemente und Platzhalter", .serialized, .renderingLock)
struct EditorThemeControlTests {
    nonisolated static let systems: [NSAppearance.Name] = [.aqua, .darkAqua]

    init() { EditorThemeSettings.shared.configure(defaults: nil, initial: .standard) }

    @Test(arguments: EditorTheme.ID.allCases, systems)
    func controlsAndDividerMeetContrast(_ id: EditorTheme.ID, _ system: NSAppearance.Name) throws {
        EditorThemeSettings.shared.select(id)
        defer { EditorThemeSettings.shared.select(.standard) }
        let editor = BlockEditorController(document: EditorDocument(blocks: [
            EditorBlock(text: "Erster Absatz"), EditorBlock(kind: .divider), EditorBlock(text: "Zweiter Absatz"),
        ]))
        let window = makeWindow(editor, system)
        let textView = editor.textView
        let manager = try #require(textView.textLayoutManager)
        let first = try #require(manager.textLayoutFragment(for: manager.documentRange.location))
        let dividerStart = try #require(manager.location(manager.documentRange.location, offsetBy: 14))
        let divider = try #require(manager.textLayoutFragment(for: dividerStart))
        #expect((divider as? BlockLayoutFragment)?.kind == .divider)
        textView.updateHandle(for: CGPoint(x: 0, y: textView.viewFrame(of: first).midY))
        #expect(!textView.handle.isHidden && !textView.insertButton.isHidden)

        let label = "\(id.rawValue), System \(suffix(system))"
        let resting = try Rendered(window, textView: textView)
        try resting.bitmap.writePNG(named: "controls-\(id.rawValue)-system-\(suffix(system))")
        let background = resting.color(at: CGPoint(x: textView.bounds.maxX - 30, y: textView.viewFrame(of: first).midY))
        expect(resting.strongestContrast(in: textView.handle.frame, against: background), 3, "Griff \(label)")
        expect(resting.strongestContrast(in: textView.insertButton.frame, against: background), 3, "Plus \(label)")
        expect(resting.strongestContrast(in: textView.viewFrame(of: divider), against: background), 3, "Trennlinie \(label)")

        textView.handle.isHovered = true
        textView.insertButton.isHovered = true
        let hovered = try Rendered(window, textView: textView)
        let plus = textView.insertButton.frame
        let fill = hovered.color(at: CGPoint(x: plus.minX + 2.5, y: plus.midY))
        expect(hovered.strongestContrast(in: textView.handle.frame, against: background), 3, "Griff bei Hover \(label)")
        expect(hovered.strongestContrast(in: plus, against: fill), 3, "Plus bei Hover \(label)")
        _ = window
    }

    @Test(arguments: EditorTheme.ID.allCases, systems)
    func emptyPageHintMeetsContrast(_ id: EditorTheme.ID, _ system: NSAppearance.Name) throws {
        EditorThemeSettings.shared.select(id)
        defer { EditorThemeSettings.shared.select(.standard) }
        let editor = BlockEditorController(document: EditorDocument())
        let window = makeWindow(editor, system)
        let textView = editor.textView
        let rect = try #require(textView.emptyPageHintRect)
        let rendered = try Rendered(window, textView: textView)
        try rendered.bitmap.writePNG(named: "hint-\(id.rawValue)-system-\(suffix(system))")
        let background = rendered.color(at: CGPoint(x: textView.bounds.maxX - 30, y: rect.midY))
        expect(rendered.strongestContrast(in: rect, against: background), 4.5, "Platzhalter \(id.rawValue), System \(suffix(system))")
        _ = window
    }

    // MARK: - Hilfen

    private func makeWindow(_ editor: BlockEditorController, _ system: NSAppearance.Name) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: system)
        window.contentView = editor.scrollView
        editor.textView.layoutSubtreeIfNeeded()
        return window
    }

    private func suffix(_ system: NSAppearance.Name) -> String { system == .aqua ? "hell" : "dunkel" }

    private func expect(_ ratio: Double, _ minimum: Double, _ what: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(ratio >= minimum, "\(what): \(String(format: "%.2f", ratio)) < \(minimum)", sourceLocation: sourceLocation)
    }

    /// Editor als Bild in doppelter Auflösung; Rechtecke in Koordinaten des Textfelds.
    @MainActor
    private struct Rendered {
        let bitmap: Bitmap
        let scrollView: NSView
        let textView: NSView
        private let scale = 2

        init(_ window: NSWindow, textView: NSView) throws {
            let view = try #require(window.contentView)
            view.layoutSubtreeIfNeeded()
            bitmap = try Bitmap(view, scale: scale)
            scrollView = view
            self.textView = textView
        }

        /// Pixelrechteck (y nach unten) zu einem Rechteck im Textfeld.
        private func pixels(_ rect: CGRect) -> (xs: Range<Int>, ys: Range<Int>) {
            let local = textView.convert(rect, to: scrollView)
            let top = scrollView.isFlipped ? local.minY : scrollView.bounds.height - local.maxY
            let s = CGFloat(scale)
            let x0 = max(0, Int((local.minX * s).rounded(.down))), x1 = min(bitmap.width, Int((local.maxX * s).rounded(.up)))
            let y0 = max(0, Int((top * s).rounded(.down))), y1 = min(bitmap.height, Int(((top + local.height) * s).rounded(.up)))
            return (x0..<max(x0, x1), y0..<max(y0, y1))
        }

        func color(at point: CGPoint) -> SRGB {
            let (xs, ys) = pixels(CGRect(origin: point, size: CGSize(width: 0.5, height: 0.5)))
            let pixel = bitmap.pixel(xs.lowerBound, ys.lowerBound)
            return SRGB(red: pixel.r, green: pixel.g, blue: pixel.b)
        }

        /// Stärkster Kontrast eines Pixels im Rechteck zu `background`.
        func strongestContrast(in rect: CGRect, against background: SRGB) -> Double {
            let (xs, ys) = pixels(rect)
            var strongest = 1.0
            for y in ys {
                for x in xs {
                    let pixel = bitmap.pixel(x, y)
                    strongest = max(strongest, SRGB(red: pixel.r, green: pixel.g, blue: pixel.b).contrast(to: background))
                }
            }
            return strongest
        }
    }
}
#endif
