#if canImport(AppKit)
import Foundation
import QuillEditor
import QuillEditorCore

/// Liest Theme (ADR-024), Fokus-Modus und Regler für Liquid Glass (ADR-036) vor dem ersten Fenster.
public enum EditorThemeSetup {
    /// Startargument `-QuillEditorTheme <id>`: Theme für UI-Tests, nur mit Test-Store.
    static let argument = "QuillEditorTheme"
    /// Startargument `-QuillTestFocusMode YES`: Fokus-Modus für UI-Tests, nur mit
    /// Test-Store. Anders benannt als der Schlüssel `QuillFocusMode`, sonst landete das
    /// Argument in der Argument-Domain von `UserDefaults` und wirkte auch ohne Test-Store.
    static let focusArgument = "QuillTestFocusMode"
    /// Startargument `-QuillTestGlass <system|0 … 1>`: Regler für Liquid Glass in UI-Tests,
    /// nur mit Test-Store; ohne das Argument „Wie System“.
    static let glassArgument = "QuillTestGlass"
    /// Startargument `-QuillTestReduceTransparency YES|NO`: „Transparenz reduzieren“ fest
    /// für UI-Tests, unabhängig von den Bedienungshilfen des Macs, nur mit Test-Store.
    static let reduceTransparencyArgument = "QuillTestReduceTransparency"

    /// UI-Tests (Debug oder Synctest A/B, `-QuillInMemoryStore` oder `-QuillStoreDirectory`) speichern
    /// keine Wahl und lesen keine: Sie dürfen Theme, Fokus-Modus und Glas des Nutzers weder
    /// ändern noch davon abhängen. Sie starten mit Standard ohne Fokus-Modus, Glas wie
    /// System, oder mit `-QuillEditorTheme <id>`, `-QuillTestFocusMode YES`,
    /// `-QuillTestGlass <Stufe>` bzw. `-QuillTestReduceTransparency YES`.
    @MainActor
    public static func configure(arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG || QUILL_SYNCTEST
        if QuillPersistence.testStore(arguments: arguments) != nil {
            func value(_ name: String) -> String? {
                arguments.firstIndex(of: "-\(name)").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            }
            EditorThemeSettings.shared.configure(defaults: nil, initial: value(argument).flatMap(EditorTheme.ID.init(rawValue:)) ?? .standard)
            EditorFocusSettings.shared.configure(defaults: nil, initial: value(focusArgument) == "YES")
            let level = value(glassArgument).flatMap(Double.init)
            let reduce = value(reduceTransparencyArgument).map { $0 == "YES" }
            GlassSettings.shared.configure(defaults: nil, followsSystem: level == nil, level: level, reduceTransparency: reduce ?? false)
            return
        }
        #endif
        EditorThemeSettings.shared.configure(defaults: .standard)
        EditorFocusSettings.shared.configure(defaults: .standard)
        GlassSettings.shared.configure(defaults: .standard)
        GlassAccessibility.start()
    }
}
#endif
