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
    static let secondaryLabel = themed(.secondary)
    /// Erledigte Aufgabe und Rahmen der leeren Checkbox.
    static let tertiaryLabel = themed(.done)
    static let quoteBar = themed(.quoteBar)
    static let codeBackground = themed(.codeBackground)
    static let selection = themed(.selection)
    static let separator: PlatformColor = .separatorColor
    static let accent = themed(.accent)
    /// Vordergrund auf Akzentfläche (Häkchen in der Checkbox).
    static let onAccent = themed(.onAccent)

    private static func themed(_ role: EditorColorRole) -> PlatformColor {
        NSColor(name: NSColor.Name("QuillEditor.\(role)")) { EditorThemeState.color(role, for: $0) }
    }
    #elseif canImport(UIKit)
    public static var background: UIColor { .systemBackground }
    public static var label: UIColor { .label }
    static var heading: PlatformColor { .label }
    static var link: PlatformColor { .link }
    static var secondaryLabel: PlatformColor { .secondaryLabel }
    static var tertiaryLabel: PlatformColor { .tertiaryLabel }
    static var quoteBar: PlatformColor { .tintColor }
    static var codeBackground: PlatformColor { .quaternarySystemFill }
    static var selection: PlatformColor { .tintColor.withAlphaComponent(0.25) }
    static var separator: PlatformColor { .separator }
    static var accent: PlatformColor { .tintColor }
    static var onAccent: PlatformColor { .white }
    #endif
}
