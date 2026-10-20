#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import QuillEditorCore
import Synchronization

/// Aktuelles Theme für die dynamischen Farben des Editors.
///
/// Die Farben lösen sich beim Zeichnen auf, auch außerhalb des Main Actors; deshalb
/// liegt der Stand hinter einem `Mutex`. Die aufgelösten Paletten werden je Variante
/// zwischengespeichert, bis ein anderes Theme kommt. Ändern nur über `EditorThemeSettings`.
enum EditorThemeState {
    private struct State {
        var theme = EditorTheme.standard
        /// „Kontrast erhöhen“ in den Bedienungshilfen.
        var increaseContrast = false
        var palettes: [EditorThemeVariant: ResolvedPalette] = [:]
    }

    private static let state = Mutex(State())
    /// Zähler im Thread-Wörterbuch, solange ein abgedunkelter Block zeichnet
    /// (`drawingDimmed`); dann liefern die Rollen ihre abgedunkelte Farbe. Je Thread,
    /// damit Farben, die woanders gleichzeitig aufgelöst werden, normal bleiben.
    private static let dimmedKey = "io.github.vogelwild07.quill.drawingDimmed"

    private static var isDrawingDimmed: Bool { (Thread.current.threadDictionary[dimmedKey] as? Int ?? 0) > 0 }

    static var theme: EditorTheme { state.withLock { $0.theme } }

    static func setTheme(_ theme: EditorTheme) {
        state.withLock { $0 = State(theme: theme, increaseContrast: $0.increaseContrast) }
    }

    static func setIncreaseContrast(_ increaseContrast: Bool) {
        state.withLock { $0 = State(theme: $0.theme, increaseContrast: increaseContrast) }
    }

    static func color(_ role: EditorColorRole, for appearance: PlatformAppearance) -> PlatformColor {
        let isDimmed = isDrawingDimmed
        let palette = palette(for: appearance)
        return isDimmed ? palette.dimmed(role) : palette[role]
    }

    /// Zeichnet `body` mit den abgedunkelten Farben des Fokus-Modus.
    static func drawingDimmed(_ body: () -> Void) {
        let dictionary = Thread.current.threadDictionary
        let depth = dictionary[dimmedKey] as? Int ?? 0
        dictionary[dimmedKey] = depth + 1
        defer { dictionary[dimmedKey] = depth }
        body()
    }

    /// Deckkraft abgedunkelter Absätze im Fokus-Modus für die Darstellung.
    static func dimmedAlpha(for appearance: PlatformAppearance) -> CGFloat {
        palette(for: appearance).dimmedAlpha
    }

    private static func palette(for appearance: PlatformAppearance) -> ResolvedPalette {
        state.withLock { state in
            let variant = EditorThemeVariant(appearance, increaseContrast: state.increaseContrast)
            if let palette = state.palettes[variant] { return palette }
            let palette = ResolvedPalette(state.theme.palette(for: variant), variant: variant)
            state.palettes[variant] = palette
            return palette
        }
    }
}

/// Farben einer Palette als Plattformfarben, gerechnet in `PaletteSpec`.
struct ResolvedPalette: Sendable {
    private let colors: [EditorColorRole: PlatformColor]
    /// Abgedunkelte Farben im Fokus-Modus (`EditorThemeState.drawingDimmed`).
    private let dimmedColors: [EditorColorRole: PlatformColor]
    /// Deckkraft abgedunkelter Absätze im Fokus-Modus (`PaletteSpec.dimmedAlpha`).
    let dimmedAlpha: CGFloat

    subscript(role: EditorColorRole) -> PlatformColor { colors[role] ?? .labelFallback }

    func dimmed(_ role: EditorColorRole) -> PlatformColor { dimmedColors[role] ?? self[role] }

    init(_ palette: EditorPalette, variant: EditorThemeVariant) {
        let spec = PaletteSpec(palette, variant: variant)
        let colors = spec.colors.mapValues(\.platformColor)
        self.colors = colors
        var dimmedColors: [EditorColorRole: PlatformColor] = [:]
        for (role, alpha) in spec.dimmedAlphas {
            dimmedColors[role] = colors[role].map { Self.faded($0, alpha: alpha) }
        }
        self.dimmedColors = dimmedColors
        dimmedAlpha = spec.dimmedAlpha
    }

    /// `color` mit Deckkraft `alpha`, weiter dynamisch: `withAlphaComponent` löst
    /// Systemfarben wie `labelColor` sonst einmal in der gerade aktuellen Darstellung auf.
    static func faded(_ color: PlatformColor, alpha: CGFloat) -> PlatformColor {
        #if canImport(AppKit)
        NSColor(name: nil) { appearance in
            var result = color
            appearance.performAsCurrentDrawingAppearance {
                result = (color.usingColorSpace(.sRGB) ?? color).withAlphaComponent(alpha)
            }
            return result
        }
        #else
        UIColor { traits in color.resolvedColor(with: traits).withAlphaComponent(alpha) }
        #endif
    }
}

extension ResolvedColor {
    var platformColor: PlatformColor {
        switch self {
        #if canImport(AppKit)
        case .srgb(let value): NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
        case .system(.textBackground): .textBackgroundColor
        case .system(.label): .labelColor
        case .system(.quaternaryFill): .quaternarySystemFill
        #else
        case .srgb(let value): UIColor(red: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
        case .system(.textBackground): .systemBackground
        case .system(.label): .label
        case .system(.quaternaryFill): .quaternarySystemFill
        #endif
        }
    }
}

extension PlatformColor {
    /// Ersatz, falls eine Rolle fehlt; im Katalog kommt das nicht vor.
    fileprivate static var labelFallback: PlatformColor {
        #if canImport(AppKit)
        .labelColor
        #else
        .label
        #endif
    }
}

/// Farben eines Themes für Ansichten außerhalb des Editors (Vorschau in den
/// Einstellungen, Seitentitel), so wie der Editor sie zeichnet.
public struct EditorThemeColors: Sendable {
    public let background, text, heading, link, secondary, quoteBar, codeBackground, accent, onAccent, done, selection: PlatformColor
}

extension EditorTheme {
    /// Feste Themes haben nur eine Variante; `dark` gilt dann nicht.
    public func colors(dark: Bool, increaseContrast: Bool) -> EditorThemeColors {
        let variant = EditorThemeVariant(dark: dark, highContrast: increaseContrast)
        let palette = ResolvedPalette(palette(for: variant), variant: variant)
        return EditorThemeColors(
            background: palette[.background], text: palette[.text], heading: palette[.heading], link: palette[.link],
            secondary: palette[.secondary], quoteBar: palette[.quoteBar], codeBackground: palette[.codeBackground],
            accent: palette[.accent], onAccent: palette[.onAccent], done: palette[.done], selection: palette[.selection]
        )
    }
}
