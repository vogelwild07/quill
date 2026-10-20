#if canImport(AppKit)
import AppKit
import Testing
@testable import QuillEditor
import QuillTestFixtures

@Suite("Theme: Katalog")
struct EditorThemeCatalogTests {
    @Test func sevenThemesInOrder() {
        #expect(EditorTheme.all.map(\.id) == EditorTheme.ID.allCases)
        #expect(EditorTheme.ID.allCases.map(\.rawValue) == ["standard", "quill", "tinte", "sonne", "lagune", "abend", "kontrast"])
        #expect(Set(EditorTheme.all.map(\.name)).count == 7)
    }

    @Test func fixedThemes() {
        let appearances = Dictionary(uniqueKeysWithValues: EditorTheme.all.map { ($0.id, $0.appearance) })
        #expect(appearances == [
            .standard: .followsSystem, .quill: .followsSystem, .tinte: .followsSystem, .kontrast: .followsSystem,
            .sonne: .light, .lagune: .dark, .abend: .dark,
        ])
        #expect(EditorTheme.with(id: .lagune).forcedAppearance?.name == .darkAqua)
        #expect(EditorTheme.with(id: .sonne).forcedAppearance?.name == .aqua)
        #expect(EditorTheme.with(id: .quill).forcedAppearance == nil)
    }

    /// „Kontrast erhöhen“ kommt aus den Bedienungshilfen, nicht nur aus dem Erscheinungsbild:
    /// Feste Themes erzwingen ein normales.
    @Test func variantFromAppearanceAndContrastSetting() {
        let dark = NSAppearance(named: .darkAqua)!
        #expect(EditorThemeVariant(dark, increaseContrast: false) == .dark)
        #expect(EditorThemeVariant(dark, increaseContrast: true) == .darkHighContrast)
        #expect(EditorThemeVariant(NSAppearance(named: .aqua)!, increaseContrast: true) == .lightHighContrast)
    }

    /// Sonnengelb aus dem Icon nur für Flächen (Zitatbalken, Auswahl, Checkbox), nie für Text.
    @Test func sunYellowNeverForText() {
        let yellow: Set<UInt32> = [0xFFC23A, 0xFFC74D]
        for theme in EditorTheme.all {
            for variant in EditorThemeVariant.allCases {
                let palette = theme.palette(for: variant)
                for color in [palette.text, palette.heading, palette.link, palette.secondary, palette.done] {
                    if case .rgb(let hex, _) = color { #expect(!yellow.contains(hex), "\(theme.id)") }
                }
            }
        }
    }
}

/// Kontrast aller Themes mit den echten, aufgelösten Farben: Text mindestens 4,5 : 1,
/// mit „Kontrast erhöhen“ 7 : 1; Häkchen und Checkbox als Grafik 3 : 1.
@MainActor
@Suite("Theme: Kontrast", .renderingLock)
struct EditorThemeContrastTests {
    @Test(arguments: EditorTheme.ID.allCases)
    func everyThemeMeetsContrast(_ id: EditorTheme.ID) {
        let problems = Self.contrastProblems(EditorTheme.with(id: id))
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    /// Gegenprobe: Ein schwaches Theme fällt durch, mit „Kontrast erhöhen“ hebt die
    /// Ableitung es auf 7 : 1.
    @Test func weakThemeFailsAndHighContrastRepairsIt() {
        let weak = EditorPalette(
            background: .rgb(0xFFFFFF), text: .rgb(0x999999), heading: .rgb(0x999999), link: .rgb(0x66BBBB),
            secondary: .rgb(0xAAAAAA), quoteBar: .rgb(0xFFC23A), codeBackground: .rgb(0xEEEEEE),
            accent: .rgb(0xBBEEEE), done: .rgb(0xBBBBBB), selection: .rgb(0x999999, alpha: 0.9)
        )
        let theme = EditorTheme(id: .standard, light: weak, dark: nil)
        let problems = Self.contrastProblems(theme)
        let normal = problems.filter { $0.hasPrefix("light:") }
        #expect(normal.count >= 6, "\(problems)")
        // Grafiken leitet „Kontrast erhöhen“ nicht ab; sie fallen weiter durch.
        #expect(problems.contains("light: Zitatbalken 1.61 < 3.0"), "\(problems)")
        let graphics = ["Checkbox", "Zitatbalken"]
        #expect(problems.allSatisfy { problem in
            !problem.hasPrefix("lightHighContrast:") || graphics.contains { problem.contains($0) }
        }, "\(problems)")
    }

    static func contrastProblems(_ theme: EditorTheme) -> [String] {
        let variants: [EditorThemeVariant] = switch theme.appearance {
        case .followsSystem: EditorThemeVariant.allCases
        case .light: [.light, .lightHighContrast]
        case .dark: [.dark, .darkHighContrast]
        }
        var problems: [String] = []
        for variant in variants {
            let palette = ResolvedPalette(theme.palette(for: variant), variant: variant)
            let appearance = NSAppearance(named: variant.appearanceName)!
            func value(_ role: EditorColorRole) -> SRGB { Self.resolve(palette[role], in: appearance) }
            let background = value(.background)
            let target = variant.isHighContrast ? ResolvedPalette.minimumHighContrast : ResolvedPalette.minimumContrast
            func check(_ name: String, _ color: SRGB, on surface: SRGB, minimum: Double) {
                let ratio = color.over(surface).contrast(to: surface)
                if ratio < minimum { problems.append("\(variant): \(name) \(String(format: "%.2f", ratio)) < \(minimum)") }
            }
            // Jede Textrolle auf Hintergrund, Codefläche (Inline-Code) und Auswahl.
            let surfaces = [("", background), (" auf Code", value(.codeBackground).over(background)),
                            (" in Auswahl", value(.selection).over(background))]
            for (name, role) in [("Text", EditorColorRole.text), ("Überschrift", .heading), ("Link", .link),
                                 ("Zitat", .secondary), ("Erledigt", .done)] {
                for (place, surface) in surfaces {
                    check(name + place, value(role), on: surface, minimum: target)
                }
            }
            let accent = value(.accent).over(background)
            check("Häkchen", value(.onAccent), on: accent, minimum: 3)
            check("Checkbox", value(.accent), on: background, minimum: 3)
            check("Zitatbalken", value(.quoteBar), on: background, minimum: 3)
            // Abgeleitete Rollen, auch mit „Kontrast erhöhen“ (gezeichnet: `EditorThemeControlTests`).
            let controlTarget = variant.isHighContrast ? ResolvedPalette.minimumHighControlContrast : ResolvedPalette.minimumControlContrast
            check("Platzhalter", value(.placeholder), on: background, minimum: target)
            check("Griff, Plus, Trennlinie", value(.control), on: background, minimum: controlTarget)
            check("Plus bei Hover", value(.secondary), on: value(.codeBackground).over(background), minimum: controlTarget)
        }
        return problems
    }

    /// Farbe in sRGB, wie sie unter dieser Darstellung gezeichnet wird.
    static func resolve(_ color: NSColor, in appearance: NSAppearance) -> SRGB {
        var result = SRGB.black
        appearance.performAsCurrentDrawingAppearance {
            let rgb = color.usingColorSpace(.sRGB)!
            result = SRGB(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
        }
        return result
    }
}

/// Wechsel wirkt sofort, ohne Text zu ändern; feste Themes erzwingen ihre Darstellung
/// nur im Editor. PNGs für die Sichtkontrolle in `$TMPDIR/QuillEditorSnapshots`.
@MainActor
@Suite("Theme: Editor", .serialized, .renderingLock)
struct EditorThemeEditorTests {
    init() { EditorThemeSettings.shared.configure(defaults: nil, initial: .standard) }

    private func makeWindow(_ editor: BlockEditorController, appearance: NSAppearance.Name) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = editor.scrollView
        editor.textView.layoutSubtreeIfNeeded()
        return window
    }

    private func render(_ window: NSWindow) throws -> Bitmap {
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        return try Bitmap(view)
    }

    /// Hintergrund unten rechts, unter dem letzten Block.
    private func background(_ bitmap: Bitmap) -> SRGB {
        let pixel = bitmap.pixel(bitmap.width - 4, bitmap.height - 4)
        return SRGB(red: pixel.r, green: pixel.g, blue: pixel.b)
    }

    private func expectClose(_ actual: SRGB, _ hex: UInt32, _ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
        let expected = SRGB(hex: hex)
        let distance = max(abs(actual.red - expected.red), abs(actual.green - expected.green), abs(actual.blue - expected.blue))
        #expect(distance < 0.02, "\(actual) statt #\(String(hex, radix: 16)) \(comment.map { "\($0)" } ?? "")", sourceLocation: sourceLocation)
    }

    @Test func switchingRedrawsWithoutTouchingText() throws {
        let editor = BlockEditorController(document: SampleDocuments.welcome)
        var changes = 0
        editor.onChange = { _ in changes += 1 }
        let window = makeWindow(editor, appearance: .aqua)
        let text = editor.textView.string
        let before = try render(window)
        expectClose(background(before), 0xFFFFFF)

        // Auf dem Bildschirm zeichnet TextKit Fragmente aus Ebenen; der Wechsel muss sie
        // verwerfen. `cacheDisplay` zeichnet ohnehin alles neu und sähe das nicht.
        let layoutManager = try #require(editor.textView.textLayoutManager)
        let fragment = try #require(layoutManager.textLayoutFragment(for: layoutManager.documentRange.location))
        #expect(fragment.state == .layoutAvailable)
        EditorThemeSettings.shared.select(.quill)
        #expect(fragment.state != .layoutAvailable, "Fragmente nach dem Wechsel verworfen")
        let quill = try render(window)
        expectClose(background(quill), 0xF7FBFA)
        #expect(quill.pixels != before.pixels)
        #expect(editor.scrollView.appearance == nil)

        // Fest dunkel: auch in einem hellen Fenster.
        EditorThemeSettings.shared.select(.lagune)
        let lagune = try render(window)
        expectClose(background(lagune), 0x062E2B)
        #expect(editor.scrollView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)

        EditorThemeSettings.shared.select(.standard)
        #expect(editor.scrollView.appearance == nil)
        let back = try render(window)
        #expect(back.pixels == before.pixels, "Zurück zu Standard zeichnet wie vorher")

        #expect(editor.textView.string == text)
        #expect(changes == 0, "Kein Speichern")
        #expect(editor.textView.undoManager?.canUndo == false, "Kein Undo-Schritt")
    }

    @Test func allEditorsFollowTheSwitch() {
        let first = BlockEditorController(document: SampleDocuments.welcome)
        let second = BlockEditorController(document: EditorDocument(blocks: [EditorBlock(text: "Zweites Fenster")]))
        EditorThemeSettings.shared.select(.abend)
        #expect(first.scrollView.appearance?.name == .darkAqua)
        #expect(second.scrollView.appearance?.name == .darkAqua)
        EditorThemeSettings.shared.select(.sonne)
        #expect(first.scrollView.appearance?.name == .aqua)
        #expect(second.scrollView.appearance?.name == .aqua)
        // Neue Editoren übernehmen das aktuelle Theme.
        let third = BlockEditorController(document: EditorDocument(blocks: [EditorBlock()]))
        #expect(third.scrollView.appearance?.name == .aqua)
        EditorThemeSettings.shared.select(.standard)
        #expect(first.scrollView.appearance == nil)
    }

    /// Jedes Theme hell und dunkel; feste Themes zeigen in beiden Fenstern ihre eine Variante.
    @Test(arguments: EditorTheme.ID.allCases)
    func snapshot(_ id: EditorTheme.ID) throws {
        let theme = EditorTheme.with(id: id)
        EditorThemeSettings.shared.select(id)
        defer { EditorThemeSettings.shared.select(.standard) }
        for system in [NSAppearance.Name.aqua, .darkAqua] {
            let editor = BlockEditorController(document: SampleDocuments.welcome)
            editor.textView.setSelectedRange(NSRange(location: 0, length: 9))
            let window = makeWindow(editor, appearance: system)
            let bitmap = try render(window)
            let suffix = system == .aqua ? "hell" : "dunkel"
            try bitmap.writePNG(named: "theme-\(id.rawValue)-system-\(suffix)")

            let variant: EditorThemeVariant = switch theme.appearance {
            case .followsSystem: system == .aqua ? .light : .dark
            case .light: .light
            case .dark: .dark
            }
            if case .rgb(let hex, _) = theme.palette(for: variant).background {
                expectClose(background(bitmap), hex, "\(id) im System \(suffix)")
            } else {
                let expected = EditorThemeContrastTests.resolve(.textBackgroundColor, in: NSAppearance(named: system)!)
                #expect(abs(background(bitmap).luminance - expected.luminance) < 0.02)
            }
        }
    }
}

@MainActor
@Suite("Theme: Einstellung", .serialized, .renderingLock)
struct EditorThemeSettingsTests {
    @Test func selectionPersistsInDefaultsOnly() throws {
        let name = "io.github.vogelwild07.quill.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer {
            defaults.removePersistentDomain(forName: name)
            EditorThemeSettings.shared.configure(defaults: nil, initial: .standard)
        }
        let settings = EditorThemeSettings.shared
        settings.configure(defaults: defaults)
        #expect(settings.selection == .standard)
        settings.select(.lagune)
        #expect(defaults.string(forKey: EditorThemeSettings.defaultsKey) == "lagune")

        // Neuer Start: gespeicherte Wahl gilt.
        settings.configure(defaults: nil, initial: .standard)
        settings.configure(defaults: defaults)
        #expect(settings.selection == .lagune)
        #expect(EditorThemeState.theme.id == .lagune)

        // Unbekannter Wert (neuere Version): Standard.
        defaults.set("neon", forKey: EditorThemeSettings.defaultsKey)
        settings.configure(defaults: defaults)
        #expect(settings.selection == .standard)
    }

    @Test func withoutDefaultsNothingIsWritten() {
        let settings = EditorThemeSettings.shared
        settings.configure(defaults: nil, initial: .abend)
        defer { settings.configure(defaults: nil, initial: .standard) }
        #expect(settings.selection == .abend)
        settings.select(.tinte)
        #expect(settings.selection == .tinte)
        #expect(EditorThemeState.theme.id == .tinte)
        #expect(UserDefaults.standard.object(forKey: EditorThemeSettings.defaultsKey) == nil)
    }
}
#endif
