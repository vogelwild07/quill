import Foundation

/// Tönung des Glases in Quill für ein Theme und eine Darstellung (ADR-036): Farbe
/// aus dem Theme, Textfarben darauf und die kleinste Deckkraft, bei der jeder Text über jedem
/// Hintergrund den Mindestkontrast hält.
///
/// Die Rechnung nimmt nichts über die Unschärfe des Glases an: Im schlimmsten Fall ist
/// das Glas so hell oder dunkel wie der Hintergrund dahinter. Über dem Glas liegt eine
/// Fläche in `color` mit mindestens `floor` Deckkraft.
package struct GlassTint: Sendable, Equatable {
    /// Hintergrundfarbe der Palette, deckend.
    package let color: SRGB
    /// Text auf dem Glas: Schwarz im Hellen, Weiß im Dunklen. Die Textfarben der Themes
    /// (Nebenfarben meist mittelgrau) bräuchten über Schwarz bzw. Weiß fast deckendes Glas.
    package let text: SRGB
    /// Nebentext: dieselbe Farbe mit `secondaryAlpha`, mit „Kontrast erhöhen“ deckend.
    package let secondary: SRGB
    /// Kleinste Deckkraft der Fläche in `color`, bei der `text` und `secondary` über
    /// allen `backdrops` den Mindestkontrast halten.
    package let floor: Double
    /// Mindestkontrast: 4,5 : 1, mit „Kontrast erhöhen“ 7 : 1 wie im Editor.
    package let minimum: Double

    /// Hintergründe hinter dem Fenster: hell, dunkel, grau und bunt.
    package static let backdrops: [SRGB] = [
        .white, .black, SRGB(hex: 0x808080),
        SRGB(hex: 0xFF0000), SRGB(hex: 0x00FF00), SRGB(hex: 0x0000FF),
        SRGB(hex: 0xFFFF00), SRGB(hex: 0x00FFFF), SRGB(hex: 0xFF00FF),
    ]
    /// Reserve über dem Mindestkontrast, wie bei den übrigen Theme-Rechnungen.
    package static let reserve = 0.1
    /// Deckkraft des Nebentexts, wie `secondaryLabel` gegenüber `label` abgestuft, aber kräftiger.
    package static let secondaryAlpha = 0.85

    /// Palette des Themes in der Darstellung des Systems. Hat ein festes Theme diese
    /// Darstellung nicht, tönt Standard: Sidebar und Toolbar folgen dem System (ADR-024).
    package init(theme: EditorTheme, dark: Bool, increaseContrast: Bool) {
        let variant = EditorThemeVariant(dark: dark, highContrast: increaseContrast)
        let own = dark ? theme.dark : theme.light
        let palette = own ?? EditorTheme.standard.palette(for: variant)
        var color = palette.background.approximation(variant)
        color.alpha = 1
        self.color = color
        text = dark ? .white : .black
        var secondary = text
        secondary.alpha = increaseContrast ? 1 : Self.secondaryAlpha
        self.secondary = secondary
        minimum = variant.isHighContrast ? PaletteSpec.minimumHighContrast : PaletteSpec.minimumContrast
        floor = Self.floor(color: color, texts: [text, secondary], minimum: minimum)
    }

    /// Deckkraft der Fläche für eine Stufe des Reglers (0 = klar, 1 = getönt).
    /// „Transparenz reduzieren“ macht deckend.
    package func opacity(level: Double, reduceTransparency: Bool) -> Double {
        if reduceTransparency { return 1 }
        let level = min(max(level, 0), 1)
        return floor + level * (1 - floor)
    }

    /// Fläche in `color` mit Deckkraft `opacity` über `backdrop`.
    package func surface(opacity: Double, over backdrop: SRGB) -> SRGB {
        var fill = color
        fill.alpha = opacity
        return fill.over(backdrop)
    }

    /// Schwächster Kontrast eines Textes über allen Hintergründen bei `opacity`.
    package func weakestContrast(opacity: Double) -> Double {
        Self.weakestContrast(color: color, texts: [text, secondary], opacity: opacity)
    }

    static func weakestContrast(color: SRGB, texts: [SRGB], opacity: Double) -> Double {
        var fill = color
        fill.alpha = opacity
        return backdrops.flatMap { backdrop in
            let surface = fill.over(backdrop)
            return texts.map { $0.over(surface).contrast(to: surface) }
        }.min() ?? 21
    }

    /// Kleinste Deckkraft in Schritten von 0,01 mit Reserve über `minimum`; 1, wenn
    /// erst die deckende Fläche reicht.
    static func floor(color: SRGB, texts: [SRGB], minimum: Double) -> Double {
        for step in 0...100 {
            let opacity = Double(step) / 100
            if weakestContrast(color: color, texts: texts, opacity: opacity) >= minimum + reserve { return opacity }
        }
        return 1
    }
}
