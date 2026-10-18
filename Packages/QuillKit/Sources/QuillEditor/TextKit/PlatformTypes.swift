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

/// Semantische Systemfarben des Editors, gleich benannt auf macOS und iOS.
enum EditorColor {
    #if canImport(AppKit)
    static var label: PlatformColor { .labelColor }
    static var secondaryLabel: PlatformColor { .secondaryLabelColor }
    static var tertiaryLabel: PlatformColor { .tertiaryLabelColor }
    static var separator: PlatformColor { .separatorColor }
    static var quaternaryFill: PlatformColor { .quaternarySystemFill }
    static var accent: PlatformColor { .controlAccentColor }
    /// Vordergrund auf Akzentfläche (Häkchen in der Checkbox).
    static var onAccent: PlatformColor { .alternateSelectedControlTextColor }
    #elseif canImport(UIKit)
    static var label: PlatformColor { .label }
    static var secondaryLabel: PlatformColor { .secondaryLabel }
    static var tertiaryLabel: PlatformColor { .tertiaryLabel }
    static var separator: PlatformColor { .separator }
    static var quaternaryFill: PlatformColor { .quaternarySystemFill }
    static var accent: PlatformColor { .tintColor }
    static var onAccent: PlatformColor { .white }
    #endif
}
