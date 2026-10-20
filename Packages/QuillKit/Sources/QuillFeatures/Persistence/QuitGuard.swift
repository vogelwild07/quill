#if canImport(AppKit)
import AppKit
import QuillEditor
import QuillEditorCore

/// Beenden mit offenen Änderungen im Editor (ADR-013): erst alles speichern; scheitert
/// das, fragen, ob trotzdem beendet werden soll. „Abbrechen“ ist die Vorgabe.
@MainActor
public enum QuitGuard {
    /// `true` = beenden.
    public static func shouldTerminate(
        flush: () async -> (any Error)? = { await EditorPersistenceBridge.flushAll() },
        confirm: (any Error) -> Bool = { confirmQuitDespite($0) }
    ) async -> Bool {
        guard let error = await flush() else { return true }
        return confirm(error)
    }

    /// Zeigt den Dialog; `true` bei „Trotzdem beenden“.
    public static func confirmQuitDespite(_ error: any Error) -> Bool {
        makeAlert(for: error).runModal() == .alertSecondButtonReturn
    }

    static func makeAlert(for error: any Error) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Änderungen konnten nicht gespeichert werden", bundle: .module)
        alert.informativeText = String(
            localized: "Wenn du Quill jetzt beendest, gehen diese Änderungen verloren. Solange Quill geöffnet bleibt, wird das Speichern weiter versucht.\n\n\(error.localizedDescription)",
            bundle: .module
        )
        let cancel = alert.addButton(withTitle: String(localized: "Abbrechen", bundle: .module))
        cancel.keyEquivalent = "\r"
        let quit = alert.addButton(withTitle: String(localized: "Trotzdem beenden", bundle: .module))
        quit.keyEquivalent = ""
        quit.hasDestructiveAction = true
        return alert
    }
}
#endif
