#if canImport(AppKit)
import Foundation
import QuillEditor

/// Liest das Theme vor dem ersten Fenster (ADR-024).
public enum EditorThemeSetup {
    /// Startargument `-QuillEditorTheme <id>`: Theme für UI-Tests, nur mit Test-Store.
    static let argument = "QuillEditorTheme"

    /// UI-Tests (Debug, `-QuillInMemoryStore` oder `-QuillStoreDirectory`) speichern
    /// keine Wahl und lesen keine: Sie dürfen das Theme des Nutzers weder ändern noch
    /// davon abhängen. Sie starten mit Standard oder `-QuillEditorTheme <id>`.
    @MainActor
    public static func configure(arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG
        if QuillPersistence.testStore(arguments: arguments) != nil {
            let id = arguments.firstIndex(of: "-\(argument)")
                .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
                .flatMap(EditorTheme.ID.init(rawValue:))
            EditorThemeSettings.shared.configure(defaults: nil, initial: id ?? .standard)
            return
        }
        #endif
        EditorThemeSettings.shared.configure(defaults: .standard)
    }
}
#endif
