#if canImport(AppKit)
import Foundation
import QuillEditor
import QuillEditorCore

/// Liest Theme (ADR-024) und Fokus-Modus vor dem ersten Fenster.
public enum EditorThemeSetup {
    /// Startargument `-QuillEditorTheme <id>`: Theme für UI-Tests, nur mit Test-Store.
    static let argument = "QuillEditorTheme"
    /// Startargument `-QuillTestFocusMode YES`: Fokus-Modus für UI-Tests, nur mit
    /// Test-Store. Anders benannt als der Schlüssel `QuillFocusMode`, sonst landete das
    /// Argument in der Argument-Domain von `UserDefaults` und wirkte auch ohne Test-Store.
    static let focusArgument = "QuillTestFocusMode"

    /// UI-Tests (Debug oder Synctest A/B, `-QuillInMemoryStore` oder `-QuillStoreDirectory`) speichern
    /// keine Wahl und lesen keine: Sie dürfen Theme und Fokus-Modus des Nutzers weder
    /// ändern noch davon abhängen. Sie starten mit Standard ohne Fokus-Modus oder mit
    /// `-QuillEditorTheme <id>` bzw. `-QuillTestFocusMode YES`.
    @MainActor
    public static func configure(arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG || QUILL_SYNCTEST
        if QuillPersistence.testStore(arguments: arguments) != nil {
            let id = arguments.firstIndex(of: "-\(argument)")
                .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
                .flatMap(EditorTheme.ID.init(rawValue:))
            EditorThemeSettings.shared.configure(defaults: nil, initial: id ?? .standard)
            let focus = arguments.firstIndex(of: "-\(focusArgument)")
                .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } == "YES"
            EditorFocusSettings.shared.configure(defaults: nil, initial: focus)
            return
        }
        #endif
        EditorThemeSettings.shared.configure(defaults: .standard)
        EditorFocusSettings.shared.configure(defaults: .standard)
    }
}
#endif
