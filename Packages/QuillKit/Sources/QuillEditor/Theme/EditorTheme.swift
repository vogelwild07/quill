#if canImport(AppKit)
import AppKit

/// Farbschema des Editors (ADR-024): Hintergrund, Text, Akzent, Überschriften,
/// Zitate, Code, Aufgaben und Auswahl. Sidebar und Symbolleiste bleiben im
/// Systemstil, Schriften ändert ein Theme nicht.
///
/// Feste Themes gibt es nur hell oder nur dunkel; der Editor zeigt sie unabhängig
/// von der Darstellung des Systems. Alle Textfarben haben mindestens 4,5 : 1 zum
/// Hintergrund, mit „Kontrast erhöhen“ mindestens 7 : 1 (`EditorThemeContrastTests`).
public struct EditorTheme: Identifiable, Sendable, Equatable {
    public enum ID: String, CaseIterable, Sendable {
        case standard, quill, tinte, sonne, lagune, abend, kontrast
    }

    public enum Appearance: Sendable, Equatable {
        case followsSystem, light, dark
    }

    public let id: ID
    let light: EditorPalette?
    let dark: EditorPalette?

    public var appearance: Appearance {
        if light == nil { return .dark }
        if dark == nil { return .light }
        return .followsSystem
    }

    public var name: String {
        switch id {
        case .standard: String(localized: "Standard", bundle: .module)
        case .quill: String(localized: "Quill", bundle: .module)
        case .tinte: String(localized: "Tinte", bundle: .module)
        case .sonne: String(localized: "Sonne", bundle: .module)
        case .lagune: String(localized: "Lagune", bundle: .module)
        case .abend: String(localized: "Abend", bundle: .module)
        case .kontrast: String(localized: "Kontrast", bundle: .module)
        }
    }

    /// Erscheinungsbild, das der Editor für ein festes Theme erzwingt; `nil` folgt dem System.
    /// Kontrastreiche Erscheinungsbilder lassen sich nicht erzeugen (`NSAppearance(named:)`
    /// liefert dafür das normale); die Theme-Farben nehmen „Kontrast erhöhen“ deshalb
    /// aus `EditorThemeState`, nicht aus dem Erscheinungsbild.
    public var forcedAppearance: NSAppearance? {
        switch appearance {
        case .followsSystem: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Farben für eine Variante; feste Themes haben nur eine.
    func palette(for variant: EditorThemeVariant) -> EditorPalette {
        let palette = variant.isDark ? (dark ?? light) : (light ?? dark)
        // Ein Theme ohne Palette gibt es im Katalog nicht (`EditorThemeCatalogTests`).
        return palette ?? EditorTheme.standard.palette(for: variant)
    }

    public static func with(id: ID) -> EditorTheme {
        all.first { $0.id == id } ?? .standard
    }

    public static let all: [EditorTheme] = [.standard, .quill, .tinte, .sonne, .lagune, .abend, .kontrast]
}

/// Hell oder dunkel, jeweils normal oder mit „Kontrast erhöhen“.
enum EditorThemeVariant: Sendable, Hashable, CaseIterable {
    case light, dark, lightHighContrast, darkHighContrast

    init(_ appearance: NSAppearance, increaseContrast: Bool) {
        let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
        let dark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
        let high = increaseContrast || match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
        switch (dark, high) {
        case (false, false): self = .light
        case (true, false): self = .dark
        case (false, true): self = .lightHighContrast
        case (true, true): self = .darkHighContrast
        }
    }

    var isDark: Bool { self == .dark || self == .darkHighContrast }
    var isHighContrast: Bool { self == .lightHighContrast || self == .darkHighContrast }

    /// Erscheinungsbild für Systemfarben; ohne kontrastreiche Varianten (siehe `forcedAppearance`).
    var appearanceName: NSAppearance.Name { isDark ? .darkAqua : .aqua }
}

/// Farben eines Themes in einer Darstellung. Sonnengelb nur für Flächen, nie für Text.
struct EditorPalette: Sendable, Equatable {
    var background: ThemeColor
    var text: ThemeColor
    var heading: ThemeColor
    var link: ThemeColor
    /// Zitat und Listenmarker.
    var secondary: ThemeColor
    var quoteBar: ThemeColor
    var codeBackground: ThemeColor
    /// Fläche der abgehakten Checkbox und Einfügelinie beim Ziehen.
    var accent: ThemeColor
    /// Erledigte Aufgabe und Rahmen der leeren Checkbox.
    var done: ThemeColor
    /// Auswahl mit Deckkraft, liegt über dem Hintergrund.
    var selection: ThemeColor
}

/// sRGB-Farbe als `0xRRGGBB` oder eine Systemfarbe (nur Theme „Standard“).
enum ThemeColor: Sendable, Equatable {
    case rgb(UInt32, alpha: Double = 1)
    case system(SystemColor)

    enum SystemColor: Sendable, Equatable {
        case textBackground, label, quaternaryFill
    }
}

extension EditorTheme {
    /// Systemfarben; Akzent, Links und Auswahl in Petrol aus dem App-Icon.
    static let standard = EditorTheme(
        id: .standard,
        light: EditorPalette(
            background: .system(.textBackground), text: .system(.label), heading: .system(.label),
            link: .rgb(0x08736C), secondary: .rgb(0x5C5C5C), quoteBar: .rgb(0x0B8F86),
            codeBackground: .system(.quaternaryFill), accent: .rgb(0x0B8F86), done: .rgb(0x6B6B6B),
            selection: .rgb(0x0B8F86, alpha: 0.25)
        ),
        dark: EditorPalette(
            background: .system(.textBackground), text: .system(.label), heading: .system(.label),
            link: .rgb(0x3DCBBE), secondary: .rgb(0xA8A8A8), quoteBar: .rgb(0x3DCBBE),
            codeBackground: .system(.quaternaryFill), accent: .rgb(0x3DCBBE), done: .rgb(0x9A9A9A),
            selection: .rgb(0x3DCBBE, alpha: 0.30)
        )
    )

    /// Signatur-Theme aus den Farben des Icons: Petrol, Tinte, Sonnengelb.
    static let quill = EditorTheme(
        id: .quill,
        light: EditorPalette(
            background: .rgb(0xF7FBFA), text: .rgb(0x1F2A33), heading: .rgb(0x0A5F5A),
            link: .rgb(0x08736C), secondary: .rgb(0x4A5862), quoteBar: .rgb(0x0B8F86),
            codeBackground: .rgb(0xE4F2F0), accent: .rgb(0x0B8F86), done: .rgb(0x5E6B74),
            selection: .rgb(0xFFC23A, alpha: 0.40)
        ),
        dark: EditorPalette(
            background: .rgb(0x151D23), text: .rgb(0xE6EBEE), heading: .rgb(0x6FDCD1),
            link: .rgb(0x3DCBBE), secondary: .rgb(0xA9B6BF), quoteBar: .rgb(0xFFC23A),
            codeBackground: .rgb(0x1D2B31), accent: .rgb(0x3DCBBE), done: .rgb(0x8E9BA4),
            selection: .rgb(0xFFC23A, alpha: 0.30)
        )
    )

    static let tinte = EditorTheme(
        id: .tinte,
        light: EditorPalette(
            background: .rgb(0xF3F5F7), text: .rgb(0x1F2A33), heading: .rgb(0x1F2A33),
            link: .rgb(0x2B6A7E), secondary: .rgb(0x4F5D68), quoteBar: .rgb(0x6E8494),
            codeBackground: .rgb(0xE5E9ED), accent: .rgb(0x2B6A7E), done: .rgb(0x5A6770),
            selection: .rgb(0x6E8494, alpha: 0.30)
        ),
        dark: EditorPalette(
            background: .rgb(0x1F2A33), text: .rgb(0xDCE3E8), heading: .rgb(0xF0F4F6),
            link: .rgb(0x8FC7D6), secondary: .rgb(0xA9B6BF), quoteBar: .rgb(0x8FA3B2),
            codeBackground: .rgb(0x28353F), accent: .rgb(0x8FC7D6), done: .rgb(0x93A1AB),
            selection: .rgb(0x8FA3B2, alpha: 0.30)
        )
    )

    static let sonne = EditorTheme(
        id: .sonne,
        light: EditorPalette(
            background: .rgb(0xFFF8E6), text: .rgb(0x2A2A1F), heading: .rgb(0x1F2A33),
            // Zitatbalken dunkles Bernstein: Sonnengelb erreicht auf Creme keine 3 : 1.
            link: .rgb(0x07706A), secondary: .rgb(0x5A5444), quoteBar: .rgb(0xB07A00),
            codeBackground: .rgb(0xFDEBBE), accent: .rgb(0x0B8F86), done: .rgb(0x6A6452),
            selection: .rgb(0xFFC23A, alpha: 0.45)
        ),
        dark: nil
    )

    static let lagune = EditorTheme(
        id: .lagune,
        light: nil,
        dark: EditorPalette(
            background: .rgb(0x062E2B), text: .rgb(0xE3F2EF), heading: .rgb(0xFFFFFF),
            link: .rgb(0x7EE3D8), secondary: .rgb(0xA8C9C4), quoteBar: .rgb(0xFFC23A),
            codeBackground: .rgb(0x0B3D39), accent: .rgb(0x3DCBBE), done: .rgb(0x8FB2AD),
            selection: .rgb(0x3DCBBE, alpha: 0.30)
        )
    )

    static let abend = EditorTheme(
        id: .abend,
        light: nil,
        dark: EditorPalette(
            background: .rgb(0x1C1A16), text: .rgb(0xEEE8DC), heading: .rgb(0xFFF4D6),
            link: .rgb(0x6FDCD1), secondary: .rgb(0xB8B0A0), quoteBar: .rgb(0xFFC23A),
            codeBackground: .rgb(0x28251F), accent: .rgb(0xFFC23A), done: .rgb(0x9E978A),
            selection: .rgb(0xFFC23A, alpha: 0.25)
        )
    )

    static let kontrast = EditorTheme(
        id: .kontrast,
        light: EditorPalette(
            background: .rgb(0xFFFFFF), text: .rgb(0x000000), heading: .rgb(0x000000),
            link: .rgb(0x004F4A), secondary: .rgb(0x262626), quoteBar: .rgb(0x0B8F86),
            codeBackground: .rgb(0xEDEDED), accent: .rgb(0x006B65), done: .rgb(0x3D3D3D),
            selection: .rgb(0xFFC23A, alpha: 0.55)
        ),
        dark: EditorPalette(
            background: .rgb(0x000000), text: .rgb(0xFFFFFF), heading: .rgb(0xFFFFFF),
            link: .rgb(0x8AF0E6), secondary: .rgb(0xE0E0E0), quoteBar: .rgb(0x3DCBBE),
            codeBackground: .rgb(0x141414), accent: .rgb(0x3DCBBE), done: .rgb(0xC8C8C8),
            selection: .rgb(0xFFC23A, alpha: 0.35)
        )
    )
}
#endif
