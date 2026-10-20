#if canImport(AppKit)
import AppKit

typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
/// Darstellung, nach der sich die Theme-Farben richten.
typealias PlatformAppearance = NSAppearance
#elseif canImport(UIKit)
import UIKit

typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
/// Darstellung, nach der sich die Theme-Farben richten.
typealias PlatformAppearance = UITraitCollection
#endif
import QuillEditorCore

/// Farben des Editors, gleich benannt auf macOS und iOS. Sie folgen dem gewählten
/// `EditorTheme` und der Darstellung (ADR-024, ADR-028).
public enum EditorColor {
    public static let background: PlatformColor = themed(.background)
    public static let label: PlatformColor = themed(.text)
    static let heading = themed(.heading)
    static let link = themed(.link)
    /// Zitat und Listenmarker.
    static let secondary = themed(.secondary)
    /// Erledigte Aufgabe und Rahmen der leeren Checkbox.
    static let done = themed(.done)
    static let quoteBar = themed(.quoteBar)
    static let codeBackground = themed(.codeBackground)
    static let selection = themed(.selection)
    /// Platzhalter der leeren Seite, mindestens 4,5 : 1.
    static let placeholder = themed(.placeholder)
    /// Ziehgriff und Plus-Knopf in Ruhe, Trennlinie; mindestens 3 : 1.
    static let control = themed(.control)
    /// Rahmen der leeren Checkbox; Farbe wie `done`, im Fokus-Modus wie eine Fläche.
    static let checkboxBorder = themed(.checkboxBorder)
    static let accent = themed(.accent)
    /// Vordergrund auf Akzentfläche (Häkchen in der Checkbox).
    static let onAccent = themed(.onAccent)

    /// Deckkraft abgedunkelter Absätze im Fokus-Modus, für die aktuelle Darstellung.
    static var dimmedAlpha: CGFloat { EditorThemeState.dimmedAlpha(for: Platform.drawingAppearance) }

    /// Zeichnet `body` mit den abgedunkelten Farben des Fokus-Modus: Textrollen behalten
    /// ihren Mindestkontrast, Flächen nehmen `dimmedAlpha`.
    static func drawingDimmed(_ body: () -> Void) { EditorThemeState.drawingDimmed(body) }

    private static func themed(_ role: EditorColorRole) -> PlatformColor {
        .dynamic(named: "QuillEditor.\(role)") { EditorThemeState.color(role, for: $0) }
    }
}

/// Die Weichen zwischen AppKit und UIKit für Farben und Bedienungshilfen, an einer
/// Stelle statt verteilt (ADR-028).
enum Platform {
    /// Darstellung, in der gerade gezeichnet wird.
    static var drawingAppearance: PlatformAppearance {
        #if canImport(AppKit)
        NSAppearance.currentDrawing()
        #else
        UITraitCollection.current
        #endif
    }

    /// „Kontrast erhöhen“ in den Bedienungshilfen (auf iOS „Dunklere Systemfarben“ in der API).
    @MainActor static var increasesContrast: Bool {
        #if canImport(AppKit)
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        #else
        UIAccessibility.isDarkerSystemColorsEnabled
        #endif
    }

    /// Benachrichtigung, wenn sich `increasesContrast` ändert, mit ihrem Center.
    @MainActor static var increasesContrastDidChange: (name: Notification.Name, center: NotificationCenter) {
        #if canImport(AppKit)
        (NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, NSWorkspace.shared.notificationCenter)
        #else
        (UIAccessibility.darkerSystemColorsStatusDidChangeNotification, .default)
        #endif
    }
}

extension PlatformColor {
    /// Farbe, die sich in jeder Darstellung neu aus `provider` ergibt. Auf iOS wird das
    /// Ergebnis in den Traits aufgelöst, falls `provider` selbst eine dynamische Farbe
    /// liefert (`label`, `systemBackground`); ob UIKit verschachtelte dynamische Farben
    /// nachauflöst, ist nicht zugesichert.
    static func dynamic(
        named name: String?,
        _ provider: @escaping @Sendable (PlatformAppearance) -> PlatformColor
    ) -> PlatformColor {
        #if canImport(AppKit)
        NSColor(name: name.map { NSColor.Name($0) }, dynamicProvider: provider)
        #else
        UIColor { traits in provider(traits).resolvedColor(with: traits) }
        #endif
    }

    /// Die Farbe, aufgelöst in `appearance`; Systemfarben wie `labelColor` werden damit fest.
    func resolved(in appearance: PlatformAppearance) -> PlatformColor {
        #if canImport(AppKit)
        var result = self
        appearance.performAsCurrentDrawingAppearance { result = self.usingColorSpace(.sRGB) ?? self }
        return result
        #else
        resolvedColor(with: appearance)
        #endif
    }

    /// Textfarbe des Systems, als Ersatz, falls eine Rolle fehlt.
    static var systemLabel: PlatformColor {
        #if canImport(AppKit)
        .labelColor
        #else
        .label
        #endif
    }
}
