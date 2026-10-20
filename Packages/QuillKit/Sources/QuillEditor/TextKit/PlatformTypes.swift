#if canImport(AppKit)
import AppKit

typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit

typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
#endif

/// Farben des Editors, gleich benannt auf macOS und iOS. Auf macOS folgen die
/// Theme-Farben dem gewählten `EditorTheme` und der Darstellung (ADR-024).
public enum EditorColor {
    #if canImport(AppKit)
    public static let background: NSColor = themed(.background)
    public static let label: NSColor = themed(.text)
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
    static let accent = themed(.accent)
    /// Vordergrund auf Akzentfläche (Häkchen in der Checkbox).
    static let onAccent = themed(.onAccent)

    /// Deckkraft abgedunkelter Absätze im Fokus-Modus, für die aktuelle Darstellung.
    static var dimmedAlpha: CGFloat { EditorThemeState.dimmedAlpha(for: NSAppearance.currentDrawing()) }

    private static func themed(_ role: EditorColorRole) -> PlatformColor {
        NSColor(name: NSColor.Name("QuillEditor.\(role)")) { EditorThemeState.color(role, for: $0) }
    }
    #elseif canImport(UIKit)
    public static var background: UIColor { .systemBackground }
    public static var label: UIColor { .label }
    static var heading: PlatformColor { .label }
    static var link: PlatformColor { .link }
    static var secondary: PlatformColor { .secondaryLabel }
    static var done: PlatformColor { .tertiaryLabel }
    static var quoteBar: PlatformColor { .tintColor }
    static var codeBackground: PlatformColor { .quaternarySystemFill }
    static var selection: PlatformColor { .tintColor.withAlphaComponent(0.25) }
    static var placeholder: PlatformColor { .placeholderText }
    static var control: PlatformColor { .tertiaryLabel }
    static var accent: PlatformColor { .tintColor }
    static var onAccent: PlatformColor { .white }
    static var dimmedAlpha: CGFloat { 0.4 }
    #endif
}
