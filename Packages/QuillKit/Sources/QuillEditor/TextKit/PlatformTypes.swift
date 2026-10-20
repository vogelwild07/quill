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
    static var dimmedAlpha: CGFloat {
        #if canImport(AppKit)
        EditorThemeState.dimmedAlpha(for: NSAppearance.currentDrawing())
        #else
        EditorThemeState.dimmedAlpha(for: UITraitCollection.current)
        #endif
    }

    /// Zeichnet `body` mit den abgedunkelten Farben des Fokus-Modus: Textrollen behalten
    /// ihren Mindestkontrast, Flächen nehmen `dimmedAlpha`.
    static func drawingDimmed(_ body: () -> Void) { EditorThemeState.drawingDimmed(body) }

    private static func themed(_ role: EditorColorRole) -> PlatformColor {
        #if canImport(AppKit)
        NSColor(name: NSColor.Name("QuillEditor.\(role)")) { EditorThemeState.color(role, for: $0) }
        #else
        UIColor { EditorThemeState.color(role, for: $0) }
        #endif
    }
}

