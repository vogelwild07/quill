import QuillDesign
import QuillEditorCore
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Glas in Quill nach dem Regler unter Einstellungen › Darstellung (ADR-036). `nil`
/// bei „Wie System“: Dann bleibt das Glas des Systems unverändert.
public struct GlassStyle: Equatable, Sendable {
    let tint: GlassTint
    /// Stufe des Reglers, 0 = klar, 1 = getönt.
    let level: Double
    let reduceTransparency: Bool

    /// Stil für die Darstellung des Systems (`dark`), aus Regler, Theme und Bedienungshilfen.
    /// In SwiftUI-Ansichten aufgerufen, beobachten sie damit alle drei.
    @MainActor
    public static func current(dark: Bool) -> GlassStyle? {
        let glass = GlassSettings.shared
        guard glass.isCustom else { return nil }
        let theme = EditorThemeSettings.shared
        return GlassStyle(
            tint: GlassTint(theme: theme.theme, dark: dark, increaseContrast: theme.increaseContrast),
            level: glass.level,
            reduceTransparency: glass.reduceTransparency
        )
    }

    /// Deckkraft der Fläche über Glas des Systems (Sidebar, Popover).
    public var opacity: Double { tint.opacity(level: level, reduceTransparency: reduceTransparency) }
    /// Deckkraft der Fläche unter eigenem Glas: der Boden; den Rest tönt das Glas selbst.
    public var floorOpacity: Double { reduceTransparency ? 1 : tint.floor }

    public var tintColor: Color { Color(tint.color) }
    public var textColor: Color { Color(tint.text) }
    public var secondaryColor: Color { Color(tint.secondary) }

    /// Eigenes Glas: klar, mit der Theme-Farbe nach der Stufe getönt.
    public var glass: Glass { Glass.clear.tint(tintColor.opacity(reduceTransparency ? 1 : level)) }

    #if canImport(AppKit)
    public var textNSColor: NSColor { NSColor(tint.text) }
    public var secondaryNSColor: NSColor { NSColor(tint.secondary) }
    #endif
}

extension Color {
    init(_ value: SRGB) {
        self.init(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }
}

#if canImport(AppKit)
extension NSColor {
    convenience init(_ value: SRGB) {
        self.init(srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
    }
}
#endif

/// Übernimmt „Transparenz reduzieren“ aus den Bedienungshilfen in `GlassSettings`.
@MainActor
public enum GlassAccessibility {
    private static var observation: NotificationObservation?

    /// Einmal beim Start; ein fester Wert aus einem Startargument bleibt (`GlassSettings`).
    public static func start() {
        GlassSettings.shared.setReduceTransparency(Platform.reducesTransparency)
        guard observation == nil else { return }
        let change = Platform.reducesTransparencyDidChange
        observation = NotificationObservation(change.name, object: nil, center: change.center) { _ in
            MainActor.assumeIsolated {
                GlassSettings.shared.setReduceTransparency(Platform.reducesTransparency)
            }
        }
    }
}

extension View {
    /// Eigenes Glas (Slash-Menü, Schnell öffnen, Schnellnotiz, Knöpfe der Toolbar): bei
    /// „Wie System“ `Glass.regular`, sonst klares, getöntes Glas über einer Fläche mit der
    /// Deckkraft des Bodens, die den Kontrast des Textes sichert (ADR-036).
    public func quillGlass<S: Shape>(in shape: S) -> some View {
        modifier(QuillGlassModifier(shape: shape))
    }

    /// Fläche über Glas des Systems, das keine API für die Tönung hat (Sidebar, Popover).
    /// Bei „Wie System“ ohne Wirkung.
    public func quillGlassTint() -> some View {
        modifier(QuillGlassTintModifier())
    }

    /// Knopf in der Toolbar mit eigener Glaskapsel; das Glas der Toolbar darunter blendet
    /// `quillToolbarGlass()` am `ToolbarItem` aus. Bei „Wie System“ ohne Wirkung.
    public func quillToolbarButtonGlass() -> some View {
        modifier(QuillToolbarButtonGlassModifier())
    }
}

extension ToolbarContent {
    /// Ohne das gemeinsame Glas der Toolbar, solange Quill das Glas steuert; die Knöpfe
    /// tragen dann `quillToolbarButtonGlass()` (ADR-036).
    @MainActor
    public func quillToolbarGlass() -> some ToolbarContent {
        sharedBackgroundVisibility(GlassSettings.shared.isCustom ? .hidden : .automatic)
    }
}

private struct QuillToolbarButtonGlassModifier: ViewModifier {
    private var glass = GlassSettings.shared

    func body(content: Content) -> some View {
        if glass.isCustom {
            content
                .padding(.horizontal, QuillDesign.Glass.toolbarHorizontalPadding)
                .padding(.vertical, QuillDesign.Glass.toolbarVerticalPadding)
                .quillGlass(in: Capsule())
        } else {
            content
        }
    }
}

private struct QuillGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if let style = GlassStyle.current(dark: colorScheme == .dark) {
            content
                .foregroundStyle(style.textColor, style.secondaryColor, style.secondaryColor)
                .background(style.tintColor.opacity(style.floorOpacity), in: shape)
                .glassEffect(style.glass, in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

private struct QuillGlassTintModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if let style = GlassStyle.current(dark: colorScheme == .dark) {
            content
                .foregroundStyle(style.textColor, style.secondaryColor, style.secondaryColor)
                .background { style.tintColor.opacity(style.opacity).ignoresSafeArea() }
        } else {
            content
        }
    }
}
