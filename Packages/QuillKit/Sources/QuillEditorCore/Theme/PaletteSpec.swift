import Foundation

/// Rollen der Theme-Farben im Editor; `EditorColor` liefert je Rolle eine dynamische Farbe.
package enum EditorColorRole: CaseIterable, Sendable {
    case background, text, heading, link, secondary, quoteBar, codeBackground, accent, onAccent, done, selection
    /// Abgeleitet: Platzhalter der leeren Seite; Ziehgriff, Plus-Knopf und Trennlinie;
    /// Rahmen der leeren Checkbox (wie `done`, im Fokus-Modus aber eine Fläche).
    case placeholder, control, checkboxBorder
}

/// Aufgelöste Farbe einer Rolle: berechnet in sRGB oder eine Systemfarbe, die die
/// Plattform je nach Darstellung liefert.
package enum ResolvedColor: Sendable, Equatable {
    case srgb(SRGB)
    case system(ThemeColor.SystemColor)
}

/// Farben einer Palette je Rolle, mit „Kontrast erhöhen“ verstärkt, und die Deckkraft
/// im Fokus-Modus. Ohne Plattform: `ResolvedPalette` in QuillEditor legt daraus
/// `NSColor` bzw. `UIColor` an (ADR-028).
package struct PaletteSpec: Sendable {
    package let colors: [EditorColorRole: ResolvedColor]
    /// Deckkraft je Rolle im Fokus-Modus, bezogen auf die Farbe der Rolle
    /// (`EditorThemeState.drawingDimmed`).
    package let dimmedAlphas: [EditorColorRole: Double]
    /// Deckkraft abgedunkelter Absätze im Fokus-Modus: Fließtext darüber Richtung
    /// Hintergrund, so weit wie möglich, aber über `minimumDimmedContrast`. Gilt auch
    /// für Kopf, Bilder und Flächen; Textrollen werden höchstens so weit abgedunkelt,
    /// dass sie den Mindestkontrast behalten.
    package let dimmedAlpha: Double

    /// Textrollen, die im Fokus-Modus den Mindestkontrast behalten.
    package static let textRoles: [EditorColorRole] = [.text, .heading, .link, .secondary, .done]

    /// Mindestkontrast von Text zum Hintergrund (WCAG AA bzw. AAA).
    package static let minimumContrast = 4.5
    package static let minimumHighContrast = 7.0
    /// Bedienelemente und Linien (WCAG 1.4.11); mit „Kontrast erhöhen“ 4,5 : 1.
    package static let minimumControlContrast = 3.0
    package static let minimumHighControlContrast = 4.5
    /// Abgedunkelter Fließtext im Fokus-Modus; mit „Kontrast erhöhen“ 4,5 : 1.
    package static let minimumDimmedContrast = 3.0
    package static let minimumHighDimmedContrast = 4.5

    package init(_ palette: EditorPalette, variant: EditorThemeVariant) {
        let background = palette.background.approximation(variant)
        let code = palette.codeBackground.approximation(variant).over(background)
        let target = variant.isHighContrast ? Self.minimumHighContrast : Self.minimumContrast

        /// Textfarben: mit „Kontrast erhöhen“ Richtung Schwarz bzw. Weiß, bis sie 7 : 1
        /// zu Hintergrund und Codefläche erreichen. Systemfarben haben eigene Varianten.
        func textColor(_ color: ThemeColor) -> (ResolvedColor, SRGB) {
            guard case .rgb = color, variant.isHighContrast else {
                return (color.resolved, color.approximation(variant))
            }
            let strong = color.approximation(variant).strengthened(against: [background, code], minimum: target)
            return (.srgb(strong), strong)
        }

        var colors: [EditorColorRole: ResolvedColor] = [:]
        var textValues: [SRGB] = []
        for (role, color) in zip(Self.textRoles, [palette.text, palette.heading, palette.link, palette.secondary, palette.done]) {
            let (resolved, value) = textColor(color)
            colors[role] = resolved
            textValues.append(value)
        }
        colors[.background] = palette.background.resolved
        colors[.codeBackground] = palette.codeBackground.resolved
        colors[.quoteBar] = palette.quoteBar.resolved
        colors[.checkboxBorder] = colors[.done]
        colors[.accent] = palette.accent.resolved
        // Platzhalter und Bedienelemente: Text Richtung Hintergrund, so zurückhaltend
        // wie möglich, aber über dem Mindestkontrast.
        let ink = textValues[0].over(background)
        let controlTarget = variant.isHighContrast ? Self.minimumHighControlContrast : Self.minimumControlContrast
        colors[.placeholder] = .srgb(ink.softened(toward: background, minimum: target))
        colors[.control] = .srgb(ink.softened(toward: background, minimum: controlTarget))
        // Häkchen auf der Akzentfläche: Weiß oder Tinte, je nachdem was stärker absetzt.
        let accent = palette.accent.approximation(variant)
        colors[.onAccent] = .srgb(SRGB.white.contrast(to: accent) >= SRGB.ink.contrast(to: accent) ? SRGB.white : SRGB.ink)

        // Auswahl: weniger deckend, bis jede Textrolle darauf das Ziel erreicht.
        var selection = palette.selection.approximation(variant)
        func textContrast(on surface: SRGB) -> Double {
            textValues.map { $0.over(surface).contrast(to: surface) }.min() ?? 21
        }
        while selection.alpha > 0.1, textContrast(on: selection.over(background)) < target {
            selection.alpha -= 0.05
        }
        colors[.selection] = .srgb(selection)
        self.colors = colors
        let dimmedTarget = variant.isHighContrast ? Self.minimumHighDimmedContrast : Self.minimumDimmedContrast
        let alpha = ink.fadedAlpha(over: background, minimum: dimmedTarget)
        dimmedAlpha = alpha
        // Jede Textrolle so weit wie der Fließtext, schwächere Rollen (Zitat, Marker,
        // Erledigt) weniger, damit sie über dem Mindestkontrast bleiben. Deckkraft
        // relativ zur eigenen, damit Systemfarben wie `labelColor` ihre behalten.
        var dimmedAlphas: [EditorColorRole: Double] = [:]
        for (role, value) in zip(Self.textRoles, textValues) {
            let roleAlpha = max(alpha, value.over(background).fadedAlpha(over: background, minimum: dimmedTarget))
            dimmedAlphas[role] = value.alpha * roleAlpha
        }
        // Flächen, Linien und Häkchen wie der Fließtext (ADR-027).
        for (role, color) in [(EditorColorRole.codeBackground, palette.codeBackground), (.quoteBar, palette.quoteBar),
                              (.accent, palette.accent), (.checkboxBorder, palette.done)] {
            dimmedAlphas[role] = color.approximation(variant).alpha * alpha
        }
        dimmedAlphas[.control] = alpha
        dimmedAlphas[.onAccent] = alpha
        self.dimmedAlphas = dimmedAlphas
    }
}

/// sRGB-Farbe mit Deckkraft, für Kontrastrechnung nach WCAG 2.
package struct SRGB: Sendable, Equatable {
    package var red, green, blue: Double
    package var alpha = 1.0

    package static let white = SRGB(red: 1, green: 1, blue: 1)
    package static let black = SRGB(red: 0, green: 0, blue: 0)
    /// Tinte aus dem App-Icon (#1F2A33).
    package static let ink = SRGB(hex: 0x1F2A33)

    package init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    package init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha
        )
    }

    package var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Kontrast zweier deckender Farben, 1 bis 21.
    package func contrast(to other: SRGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Diese Farbe mit ihrer Deckkraft über `background`.
    package func over(_ background: SRGB) -> SRGB {
        func mix(_ top: Double, _ bottom: Double) -> Double { top * alpha + bottom * (1 - alpha) }
        return SRGB(red: mix(red, background.red), green: mix(green, background.green), blue: mix(blue, background.blue))
    }

    /// In Schritten Richtung Schwarz (heller Hintergrund) oder Weiß, bis der Kontrast
    /// zu allen Hintergründen reicht.
    package func strengthened(against backgrounds: [SRGB], minimum: Double) -> SRGB {
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
    package func softened(toward background: SRGB, minimum: Double) -> SRGB {
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
    package func fadedAlpha(over background: SRGB, minimum: Double) -> Double {
        var result = 1.0
        for alpha in stride(from: 0.95, through: 0.05, by: -0.05) {
            var faded = self
            faded.alpha = self.alpha * alpha
            guard faded.over(background).contrast(to: background) >= minimum + 0.1 else { break }
            result = alpha
        }
        return result
    }

}

extension ThemeColor {
    /// Farbe ohne Kontrastrechnung: Hex-Wert als sRGB oder die Systemfarbe.
    package var resolved: ResolvedColor {
        switch self {
        case .rgb(let hex, let alpha): .srgb(SRGB(hex: hex, alpha: alpha))
        case .system(let color): .system(color)
        }
    }

    /// Wert für die Kontrastrechnung. Systemfarben als Näherung ihrer Werte unter
    /// macOS 26, auch mit „Kontrast erhöhen“ die normalen: Die kontrastreichen setzen
    /// sich stärker ab, und nur die normalen kann der Test auflösen (`EditorThemeContrastTests`).
    package func approximation(_ variant: EditorThemeVariant) -> SRGB {
        switch self {
        case .rgb(let hex, let alpha): SRGB(hex: hex, alpha: alpha)
        case .system(.textBackground): variant.isDark ? SRGB(hex: 0x1E1E1E) : .white
        case .system(.label): SRGB(hex: variant.isDark ? 0xFFFFFF : 0x000000, alpha: 0.85)
        case .system(.quaternaryFill): SRGB(hex: variant.isDark ? 0xFFFFFF : 0x000000, alpha: variant.isDark ? 0.10 : 0.05)
        }
    }
}
