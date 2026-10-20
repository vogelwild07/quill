#if canImport(AppKit)
import AppKit
import QuillTestFixtures
import Testing
@testable import QuillEditor

/// Fokus-Modus (Phase 18.1): abgedunkelte Umgebung in Richtung Theme-Hintergrund,
/// Fließtext darin mindestens 3 : 1 (mit „Kontrast erhöhen“ 4,5 : 1), und
/// Schreibmaschinen-Scrollen. Fokus-Modus und Theme gelten prozessweit, deshalb
/// `.renderingLock`. PNGs in `$TMPDIR/QuillEditorSnapshots` (`focus-<theme>-system-<hell|dunkel>`).
@MainActor
@Suite("Fokus-Modus", .serialized, .renderingLock)
struct EditorFocusModeTests {
    nonisolated static let systems: [NSAppearance.Name] = [.aqua, .darkAqua]

    init() {
        EditorThemeSettings.shared.configure(defaults: nil, initial: .standard)
        EditorFocusSettings.shared.configure(defaults: nil, initial: false)
    }

    // MARK: Farben

    /// Jedes Theme in jeder Variante: abgedunkelter Fließtext über dem Mindestkontrast,
    /// aber sichtbar zurückgenommen.
    @Test(arguments: EditorTheme.ID.allCases)
    func dimmedTextKeepsMinimumContrast(_ id: EditorTheme.ID) {
        let theme = EditorTheme.with(id: id)
        let variants: [EditorThemeVariant] = switch theme.appearance {
        case .followsSystem: EditorThemeVariant.allCases
        case .light: [.light, .lightHighContrast]
        case .dark: [.dark, .darkHighContrast]
        }
        for variant in variants {
            let palette = ResolvedPalette(theme.palette(for: variant), variant: variant)
            let appearance = NSAppearance(named: variant.appearanceName)!
            let background = EditorThemeContrastTests.resolve(palette[.background], in: appearance)
            var text = EditorThemeContrastTests.resolve(palette[.text], in: appearance).over(background)
            let full = text.contrast(to: background)
            text.alpha = palette.dimmedAlpha
            let dimmed = text.over(background).contrast(to: background)
            // Feste Werte statt der Konstanten, damit eine geänderte Konstante auffällt.
            let minimum = variant.isHighContrast ? 4.5 : 3.0
            #expect(dimmed >= minimum, "\(id.rawValue) \(variant): \(String(format: "%.2f", dimmed)) < \(minimum)")
            #expect(palette.dimmedAlpha <= 0.8, "\(id.rawValue) \(variant): kaum abgedunkelt (\(palette.dimmedAlpha))")
            #expect(dimmed < full, "\(id.rawValue) \(variant)")
        }
    }

    /// Gezeichnet in jedem Theme bei hellem und dunklem System: Der Block mit dem Cursor
    /// bleibt wie er ist, die anderen sind schwächer, aber mindestens 3 : 1.
    @Test(arguments: EditorTheme.ID.allCases, systems)
    func otherBlocksAreDimmedWhenDrawn(_ id: EditorTheme.ID, _ system: NSAppearance.Name) throws {
        EditorThemeSettings.shared.select(id)
        defer { EditorThemeSettings.shared.select(.standard) }
        let editor = BlockEditorController(document: Self.threeParagraphs)
        let window = makeWindow(editor, system, height: 300)
        let label = "\(id.rawValue), System \(system == .aqua ? "hell" : "dunkel")"
        caret(editor, inBlock: 1)
        let plain = try Rendered(window, textView: editor.textView)
        let background = plain.color(at: CGPoint(x: editor.textView.bounds.maxX - 30, y: try frame(editor, block: 0).midY))
        let before = plain.strongestContrast(in: try frame(editor, block: 0), against: background)

        EditorFocusSettings.shared.setEnabled(true)
        defer { EditorFocusSettings.shared.setEnabled(false) }
        let focused = try Rendered(window, textView: editor.textView)
        try focused.bitmap.writePNG(named: "focus-\(id.rawValue)-system-\(system == .aqua ? "hell" : "dunkel")")
        let dimmed = focused.strongestContrast(in: try frame(editor, block: 0), against: background)
        let active = focused.strongestContrast(in: try frame(editor, block: 1), against: background)
        #expect(dimmed >= 3, "\(label): \(String(format: "%.2f", dimmed))")
        #expect(dimmed < active / 1.4, "\(label): abgedunkelt \(String(format: "%.2f", dimmed)), aktiv \(String(format: "%.2f", active))")
        #expect(abs(active - before) < 0.5, "\(label): aktiver Block unverändert")
        _ = window
    }

    // MARK: Abdunkeln

    @Test func onlyBlocksWithCaretOrSelectionStayBright() throws {
        let editor = BlockEditorController(document: Self.threeParagraphs)
        let window = makeWindow(editor, .aqua, height: 300)
        caret(editor, inBlock: 1)
        #expect(try dimmedBlocks(editor) == [], "Ohne Fokus-Modus nichts abgedunkelt")

        EditorFocusSettings.shared.setEnabled(true)
        defer { EditorFocusSettings.shared.setEnabled(false) }
        #expect(try dimmedBlocks(editor) == [0, 2])

        caret(editor, inBlock: 2)
        editor.updateFocusedBlocks()
        #expect(try dimmedBlocks(editor) == [0, 1])

        // Auswahl über zwei Blöcke: beide hell.
        editor.textView.setSelectedRange(NSRange(location: editor.paragraphStarts[0] + 2, length: editor.paragraphStarts[1] - 1))
        editor.updateFocusedBlocks()
        #expect(try dimmedBlocks(editor) == [2])

        // Fokus im Titel oder in der Sidebar: nichts abgedunkelt.
        window.makeFirstResponder(nil)
        editor.updateFocusedBlocks()
        #expect(try dimmedBlocks(editor) == [])

        window.makeFirstResponder(editor.textView)
        caret(editor, inBlock: 0)
        EditorFocusSettings.shared.setEnabled(false)
        #expect(try dimmedBlocks(editor) == [])
    }

    /// Auswahländerungen gleicht der Editor selbst ab, am Ende des Run-Loop-Durchlaufs.
    @Test func selectionChangeUpdatesDimmingByItself() async throws {
        let editor = BlockEditorController(document: Self.threeParagraphs)
        let window = makeWindow(editor, .aqua, height: 300)
        caret(editor, inBlock: 0)
        EditorFocusSettings.shared.setEnabled(true)
        defer { EditorFocusSettings.shared.setEnabled(false) }
        #expect(try dimmedBlocks(editor) == [1, 2])

        editor.textView.setSelectedRange(NSRange(location: editor.paragraphStarts[2] + 1, length: 0))
        try await Task.sleep(for: .milliseconds(50))
        #expect(try dimmedBlocks(editor) == [0, 1])
        _ = window
    }

    @Test func headerIsDimmedWhileTextHasFocus() throws {
        let editor = BlockEditorController(document: Self.threeParagraphs)
        let header = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        editor.header = header
        let window = makeWindow(editor, .aqua, height: 300)
        caret(editor, inBlock: 1)
        EditorFocusSettings.shared.setEnabled(true)
        defer { EditorFocusSettings.shared.setEnabled(false) }
        #expect(header.alphaValue < 1)
        window.makeFirstResponder(nil)
        editor.updateFocusedBlocks()
        #expect(header.alphaValue == 1)
        window.makeFirstResponder(editor.textView)
        editor.updateFocusedBlocks()
        EditorFocusSettings.shared.setEnabled(false)
        #expect(header.alphaValue == 1)
    }

    /// Ein- und Ausschalten ändert weder Text noch Undo und meldet keine Änderung.
    @Test func togglingTouchesNeitherTextNorUndo() {
        let editor = BlockEditorController(document: Self.threeParagraphs)
        let window = makeWindow(editor, .aqua, height: 300)
        var changes = 0
        editor.onChange = { _ in changes += 1 }
        let text = editor.textView.string
        EditorFocusSettings.shared.setEnabled(true)
        EditorFocusSettings.shared.setEnabled(false)
        #expect(editor.textView.string == text)
        #expect(editor.document == Self.threeParagraphs)
        #expect(changes == 0)
        #expect(editor.textView.undoManager?.canUndo != true)
        _ = window
    }

    // MARK: Schreibmaschinen-Scrollen

    @Test func caretLineStaysInTheMiddle() throws {
        let blocks = (1...60).map { EditorBlock(text: "Absatz \($0)") }
        let editor = BlockEditorController(document: EditorDocument(blocks: blocks))
        let window = makeWindow(editor, .aqua, height: 300)
        let clip = editor.scrollView.contentView
        let naturalHeight = editor.textView.frame.height

        EditorFocusSettings.shared.setEnabled(true)
        defer { EditorFocusSettings.shared.setEnabled(false) }
        #expect(editor.textView.frame.height >= naturalHeight + clip.bounds.height / 2 - 1, "Platz unter dem Text")

        for block in [30, 59] {
            caret(editor, inBlock: block)
            editor.centerCaret(animated: false)
            let caretRect = try #require(editor.caretRect(at: editor.caretLocation))
            let insets = clip.contentInsets
            let middle = clip.bounds.minY + insets.top + (clip.bounds.height - insets.top - insets.bottom) / 2
            let offset = caretRect.midY - middle
            #expect(abs(offset) <= 2, "Block \(block): \(offset) pt neben der Mitte")
        }

        // Am Anfang bleibt der Text oben, statt in die Mitte zu rutschen.
        caret(editor, inBlock: 0)
        editor.centerCaret(animated: false)
        #expect(clip.bounds.minY == 0)

        // Bei einer Auswahl wird nicht gescrollt.
        caret(editor, inBlock: 40)
        editor.centerCaret(animated: false)
        let origin = clip.bounds.origin
        editor.textView.setSelectedRange(NSRange(location: editor.paragraphStarts[10], length: 30))
        editor.centerCaret(animated: false)
        #expect(clip.bounds.origin == origin)

        // Die Texthöhe selbst steht erst nach dem Scrollen fest (vorher geschätzt).
        let focusedHeight = editor.textView.frame.height
        EditorFocusSettings.shared.setEnabled(false)
        #expect(editor.textView.frame.height == focusedHeight - ceil(clip.bounds.height / 2), "Platz wieder weg")
        _ = window
    }

    // MARK: Einstellung

    @Test func choicePersistsInDefaultsOnly() throws {
        let name = "io.github.vogelwild07.quill.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer {
            defaults.removePersistentDomain(forName: name)
            EditorFocusSettings.shared.configure(defaults: nil, initial: false)
        }
        let settings = EditorFocusSettings.shared
        settings.configure(defaults: defaults)
        #expect(!settings.isEnabled)
        settings.toggle()
        #expect(defaults.bool(forKey: EditorFocusSettings.defaultsKey))

        settings.configure(defaults: nil, initial: false)
        settings.configure(defaults: defaults)
        #expect(settings.isEnabled, "Neuer Start: gespeicherte Wahl gilt")

        settings.configure(defaults: nil, initial: false)
        settings.setEnabled(true)
        #expect(UserDefaults.standard.object(forKey: EditorFocusSettings.defaultsKey) == nil, "Ohne Defaults nichts geschrieben")
    }

    // MARK: - Hilfen

    static let threeParagraphs = EditorDocument(blocks: [
        EditorBlock(text: "Erster Absatz mit etwas Text"),
        EditorBlock(text: "Zweiter Absatz mit etwas Text"),
        EditorBlock(text: "Dritter Absatz mit etwas Text"),
    ])

    private func makeWindow(_ editor: BlockEditorController, _ system: NSAppearance.Name, height: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: height), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: system)
        window.contentView = editor.scrollView
        window.makeFirstResponder(editor.textView)
        editor.textView.layoutSubtreeIfNeeded()
        return window
    }

    private func caret(_ editor: BlockEditorController, inBlock index: Int) {
        editor.textView.setSelectedRange(NSRange(location: editor.paragraphStarts[index] + 1, length: 0))
    }

    private func fragment(_ editor: BlockEditorController, block index: Int) throws -> BlockLayoutFragment {
        let manager = try #require(editor.textView.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        let location = try #require(manager.location(manager.documentRange.location, offsetBy: editor.paragraphStarts[index]))
        return try #require(manager.textLayoutFragment(for: location) as? BlockLayoutFragment)
    }

    private func frame(_ editor: BlockEditorController, block index: Int) throws -> CGRect {
        editor.textView.viewFrame(of: try fragment(editor, block: index))
    }

    private func dimmedBlocks(_ editor: BlockEditorController) throws -> [Int] {
        try editor.document.blocks.indices.filter { try fragment(editor, block: $0).isDimmed }
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
