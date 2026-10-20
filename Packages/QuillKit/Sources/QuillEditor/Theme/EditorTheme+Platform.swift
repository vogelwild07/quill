#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import QuillEditorCore

/// Teile von `EditorTheme`, die Oberfläche oder Plattform brauchen: lokalisierter Name,
/// erzwungene Darstellung fester Themes, Variante aus der Darstellung (ADR-024, ADR-028).
extension EditorTheme {
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

    #if canImport(AppKit)
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
    #elseif canImport(UIKit)
    /// Interface-Stil, den der Editor für ein festes Theme erzwingt; `.unspecified` folgt dem System.
    public var forcedInterfaceStyle: UIUserInterfaceStyle {
        switch appearance {
        case .followsSystem: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
    #endif
}

extension EditorThemeVariant {
    #if canImport(AppKit)
    init(_ appearance: NSAppearance, increaseContrast: Bool) {
        let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
        let dark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
        let high = increaseContrast || match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
        self.init(dark: dark, highContrast: high)
    }

    /// Erscheinungsbild für Systemfarben; ohne kontrastreiche Varianten (siehe `forcedAppearance`).
    var appearanceName: NSAppearance.Name { isDark ? .darkAqua : .aqua }
    #elseif canImport(UIKit)
    /// „Kontrast erhöhen“ steckt auf iOS in den Traits (`accessibilityContrast`).
    init(_ traits: UITraitCollection, increaseContrast: Bool) {
        self.init(
            dark: traits.userInterfaceStyle == .dark,
            highContrast: increaseContrast || traits.accessibilityContrast == .high
        )
    }
    #endif
}
