#if canImport(AppKit)
import AppKit
import Synchronization

/// Rollen der Theme-Farben im Editor; `EditorColor` liefert je Rolle eine dynamische Farbe.
enum EditorColorRole: CaseIterable, Sendable {
    case background, text, heading, link, secondary, quoteBar, codeBackground, accent, onAccent, done, selection
    /// Abgeleitet: Platzhalter der leeren Seite; Ziehgriff, Plus-Knopf und Trennlinie.
    case placeholder, control
}

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

    static var theme: EditorTheme { state.withLock { $0.theme } }

    static func setTheme(_ theme: EditorTheme) {
        state.withLock { $0 = State(theme: theme, increaseContrast: $0.increaseContrast) }
    }

    static func setIncreaseContrast(_ increaseContrast: Bool) {
        state.withLock { $0 = State(theme: $0.theme, increaseContrast: increaseContrast) }
    }

    static func color(_ role: EditorColorRole, for appearance: NSAppearance) -> NSColor {
        state.withLock { state in
            let variant = EditorThemeVariant(appearance, increaseContrast: state.increaseContrast)
            if let palette = state.palettes[variant] { return palette[role] }
            let palette = ResolvedPalette(state.theme.palette(for: variant), variant: variant)
            state.palettes[variant] = palette
            return palette[role]
        }
    }

    /// Deckkraft abgedunkelter Absätze im Fokus-Modus für die Darstellung.
    static func dimmedAlpha(for appearance: NSAppearance) -> CGFloat {
        state.withLock { state in
            let variant = EditorThemeVariant(appearance, increaseContrast: state.increaseContrast)
            if let palette = state.palettes[variant] { return palette.dimmedAlpha }
            let palette = ResolvedPalette(state.theme.palette(for: variant), variant: variant)
            state.palettes[variant] = palette
            return palette.dimmedAlpha
        }
    }
}

/// Farben einer Palette als `NSColor`, mit „Kontrast erhöhen“ verstärkt.
struct ResolvedPalette: Sendable {
    private let colors: [EditorColorRole: NSColor]
    /// Deckkraft abgedunkelter Absätze im Fokus-Modus: Fließtext darüber Richtung
    /// Hintergrund, so weit wie möglich, aber über `minimumDimmedContrast`.
    let dimmedAlpha: CGFloat

    subscript(role: EditorColorRole) -> NSColor { colors[role] ?? .labelColor }

    /// Mindestkontrast von Text zum Hintergrund (WCAG AA bzw. AAA).
    static let minimumContrast = 4.5
    static let minimumHighContrast = 7.0
    /// Bedienelemente und Linien (WCAG 1.4.11); mit „Kontrast erhöhen“ 4,5 : 1.
    static let minimumControlContrast = 3.0
    static let minimumHighControlContrast = 4.5
    /// Abgedunkelter Fließtext im Fokus-Modus; mit „Kontrast erhöhen“ 4,5 : 1.
    static let minimumDimmedContrast = 3.0
    static let minimumHighDimmedContrast = 4.5

    init(_ palette: EditorPalette, variant: EditorThemeVariant) {
        let background = palette.background.approximation(variant)
        let code = palette.codeBackground.approximation(variant).over(background)
        let target = variant.isHighContrast ? Self.minimumHighContrast : Self.minimumContrast

        /// Textfarben: mit „Kontrast erhöhen“ Richtung Schwarz bzw. Weiß, bis sie 7 : 1
        /// zu Hintergrund und Codefläche erreichen. Systemfarben haben eigene Varianten.
        func textColor(_ color: ThemeColor) -> (NSColor, SRGB) {
            guard case .rgb = color, variant.isHighContrast else {
                return (color.nsColor, color.approximation(variant))
            }
            let strong = color.approximation(variant).strengthened(against: [background, code], minimum: target)
            return (strong.nsColor, strong)
        }

        var colors: [EditorColorRole: NSColor] = [:]
        var textValues: [SRGB] = []
        for (role, color) in [(EditorColorRole.text, palette.text), (.heading, palette.heading), (.link, palette.link),
                              (.secondary, palette.secondary), (.done, palette.done)] {
            let (resolved, value) = textColor(color)
            colors[role] = resolved
            textValues.append(value)
        }
        colors[.background] = palette.background.nsColor
        colors[.codeBackground] = palette.codeBackground.nsColor
        colors[.quoteBar] = palette.quoteBar.nsColor
        colors[.accent] = palette.accent.nsColor
        // Platzhalter und Bedienelemente: Text Richtung Hintergrund, so zurückhaltend
        // wie möglich, aber über dem Mindestkontrast.
        let ink = textValues[0].over(background)
        let controlTarget = variant.isHighContrast ? Self.minimumHighControlContrast : Self.minimumControlContrast
        colors[.placeholder] = ink.softened(toward: background, minimum: target).nsColor
        colors[.control] = ink.softened(toward: background, minimum: controlTarget).nsColor
        // Häkchen auf der Akzentfläche: Weiß oder Tinte, je nachdem was stärker absetzt.
        let accent = palette.accent.approximation(variant)
        colors[.onAccent] = (SRGB.white.contrast(to: accent) >= SRGB.ink.contrast(to: accent) ? SRGB.white : SRGB.ink).nsColor

        // Auswahl: weniger deckend, bis jede Textrolle darauf das Ziel erreicht.
        var selection = palette.selection.approximation(variant)
        func textContrast(on surface: SRGB) -> Double {
            textValues.map { $0.over(surface).contrast(to: surface) }.min() ?? 21
        }
        while selection.alpha > 0.1, textContrast(on: selection.over(background)) < target {
            selection.alpha -= 0.05
        }
        colors[.selection] = selection.nsColor
        self.colors = colors
        let dimmedTarget = variant.isHighContrast ? Self.minimumHighDimmedContrast : Self.minimumDimmedContrast
        dimmedAlpha = ink.fadedAlpha(over: background, minimum: dimmedTarget)
    }
}

/// sRGB-Farbe mit Deckkraft, für Kontrastrechnung nach WCAG 2.
struct SRGB: Sendable, Equatable {
    var red, green, blue: Double
    var alpha = 1.0

    static let white = SRGB(red: 1, green: 1, blue: 1)
    static let black = SRGB(red: 0, green: 0, blue: 0)
    /// Tinte aus dem App-Icon (#1F2A33).
    static let ink = SRGB(hex: 0x1F2A33)

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha
        )
    }

    var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Kontrast zweier deckender Farben, 1 bis 21.
    func contrast(to other: SRGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Diese Farbe mit ihrer Deckkraft über `background`.
    func over(_ background: SRGB) -> SRGB {
        func mix(_ top: Double, _ bottom: Double) -> Double { top * alpha + bottom * (1 - alpha) }
        return SRGB(red: mix(red, background.red), green: mix(green, background.green), blue: mix(blue, background.blue))
    }

    /// In Schritten Richtung Schwarz (heller Hintergrund) oder Weiß, bis der Kontrast
    /// zu allen Hintergründen reicht.
    func strengthened(against backgrounds: [SRGB], minimum: Double) -> SRGB {
        let lightBackground = (backgrounds.first?.luminance ?? 1) > 0.18
        let extreme = lightBackground ? SRGB.black : SRGB.white
        var color = self
        var step = 0.0
        while step < 1, backgrounds.contains(where: { color.contrast(to: $0) < minimum }) {
            step += 0.05
            color = SRGB(red: red + (extreme.red - red) * step, green: green + (extreme.green - green) * step,
                         blue: blue + (extreme.blue - blue) * step, alpha: alpha)
        }
        return color
    }

    /// In Schritten Richtung `background`, solange der Kontrast mit etwas Reserve über
    /// `minimum` bleibt.
    func softened(toward background: SRGB, minimum: Double) -> SRGB {
        var color = self
        for step in stride(from: 0.05, through: 1, by: 0.05) {
            let next = SRGB(red: red + (background.red - red) * step, green: green + (background.green - green) * step,
                            blue: blue + (background.blue - blue) * step, alpha: alpha)
            guard next.contrast(to: background) >= minimum + 0.1 else { break }
            color = next
        }
        return color
    }

    /// Kleinste Deckkraft in Schritten von 0,05, bei der diese Farbe über `background`
    /// mit etwas Reserve über `minimum` bleibt; 1, wenn sie das schon deckend nicht schafft.
    func fadedAlpha(over background: SRGB, minimum: Double) -> CGFloat {
        var result = 1.0
        for alpha in stride(from: 0.95, through: 0.05, by: -0.05) {
            var faded = self
            faded.alpha = self.alpha * alpha
            guard faded.over(background).contrast(to: background) >= minimum + 0.1 else { break }
            result = alpha
        }
        return result
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

extension ThemeColor {
    var nsColor: NSColor {
        switch self {
        case .rgb(let hex, let alpha): SRGB(hex: hex, alpha: alpha).nsColor
        case .system(.textBackground): .textBackgroundColor
        case .system(.label): .labelColor
        case .system(.quaternaryFill): .quaternarySystemFill
        }
    }

    /// Wert für die Kontrastrechnung. Systemfarben als Näherung ihrer Werte unter
    /// macOS 26, auch mit „Kontrast erhöhen“ die normalen: Die kontrastreichen setzen
    /// sich stärker ab, und nur die normalen kann der Test auflösen (`EditorThemeContrastTests`).
    func approximation(_ variant: EditorThemeVariant) -> SRGB {
        switch self {
        case .rgb(let hex, let alpha): SRGB(hex: hex, alpha: alpha)
        case .system(.textBackground): variant.isDark ? SRGB(hex: 0x1E1E1E) : .white
        case .system(.label): SRGB(hex: variant.isDark ? 0xFFFFFF : 0x000000, alpha: 0.85)
        case .system(.quaternaryFill): SRGB(hex: variant.isDark ? 0xFFFFFF : 0x000000, alpha: variant.isDark ? 0.10 : 0.05)
        }
    }
}
#endif

#if canImport(AppKit)
/// Farben eines Themes für Ansichten außerhalb des Editors (Vorschau in den
/// Einstellungen, Seitentitel), so wie der Editor sie zeichnet.
public struct EditorThemeColors: Sendable {
    public let background, text, heading, link, secondary, quoteBar, codeBackground, accent, onAccent, done, selection: NSColor
}

extension EditorTheme {
    /// Feste Themes haben nur eine Variante; `dark` gilt dann nicht.
    public func colors(dark: Bool, increaseContrast: Bool) -> EditorThemeColors {
        let variant: EditorThemeVariant = switch (dark, increaseContrast) {
        case (false, false): .light
        case (true, false): .dark
        case (false, true): .lightHighContrast
        case (true, true): .darkHighContrast
        }
        let palette = ResolvedPalette(palette(for: variant), variant: variant)
        return EditorThemeColors(
            background: palette[.background], text: palette[.text], heading: palette[.heading], link: palette[.link],
            secondary: palette[.secondary], quoteBar: palette[.quoteBar], codeBackground: palette[.codeBackground],
            accent: palette[.accent], onAccent: palette[.onAccent], done: palette[.done], selection: palette[.selection]
        )
    }
}
#endif
