#if canImport(AppKit)
import AppKit

/// Rückfrage, bevor Quill die Datenbank auf ein neues Schema umstellt (Phase 11.2,
/// ADR-029). „Beenden“ ist der Standardknopf (Return); „Umstellen“ hat kein Tastenkürzel
/// und muss bewusst angeklickt werden.
@MainActor
public enum MigrationPrompt {
    static let quitIdentifier = "migration.quit"
    static let migrateIdentifier = "migration.migrate"

    /// Zeigt die Rückfrage modal. Erst aufrufen, wenn die App gestartet ist, sonst ist
    /// der Dialog für Bedienungshilfen (VoiceOver, UI-Tests) nicht erreichbar.
    public static func ask(from: String?, to: String) -> QuillPersistence.MigrationAnswer {
        let alert = makeAlert()
        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn ? .migrate : .quit
    }

    static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Datenbank umstellen?", bundle: .module)
        alert.informativeText = String(
            localized: "Diese Version von Quill braucht ein neues Format für deine Daten. Vorher legt Quill ein Backup an. Ältere Versionen von Quill können die Daten danach nicht mehr öffnen.",
            bundle: .module
        )
        let quit = alert.addButton(withTitle: String(localized: "Beenden", bundle: .module))
        quit.keyEquivalent = "\r"
        quit.setAccessibilityIdentifier(quitIdentifier)
        let migrate = alert.addButton(withTitle: String(localized: "Umstellen", bundle: .module))
        migrate.keyEquivalent = ""
        migrate.setAccessibilityIdentifier(migrateIdentifier)
        return alert
    }
}
#endif
