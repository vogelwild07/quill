#if canImport(AppKit)
import AppKit

/// Rückfrage, bevor Quill die Datenbank auf ein neues Schema umstellt (Phase 11.2,
/// ADR-029). „Beenden“ ist der Standardknopf (Return), Escape wählt es auch; „Umstellen“
/// hat kein Tastenkürzel und muss bewusst angeklickt werden.
@MainActor
public enum MigrationPrompt {
    static let quitIdentifier = "migration.quit"
    static let migrateIdentifier = "migration.migrate"

    /// Zeigt die Rückfrage modal. Erst aufrufen, wenn die App gestartet ist, sonst ist
    /// der Dialog für Bedienungshilfen (VoiceOver, UI-Tests) nicht erreichbar.
    public static func ask(from: String?, to: String) -> QuillPersistence.MigrationAnswer {
        let alert = makeAlert()
        alert.layout()
        // Ein Knopf hat nur ein Tastenkürzel (Return): Escape fängt der Monitor ab.
        let escape = escapeHandler(for: alert) { NSApp.stopModal(withCode: $0) }
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: escape)
        defer { monitor.map(NSEvent.removeMonitor) }
        NSApp.activate()
        return answer(for: alert.runModal())
    }

    static func answer(for response: NSApplication.ModalResponse) -> QuillPersistence.MigrationAnswer {
        response == .alertSecondButtonReturn ? .migrate : .quit
    }

    /// Escape im Fenster der Rückfrage beendet sie wie „Beenden“; alle anderen Tasten
    /// gehen unverändert weiter.
    static func escapeHandler(
        for alert: NSAlert,
        stop: @escaping @MainActor (NSApplication.ModalResponse) -> Void
    ) -> (NSEvent) -> NSEvent? {
        { event in
            guard event.type == .keyDown, event.keyCode == escapeKeyCode else { return event }
            let windowNumber = event.windowNumber
            let consumed = MainActor.assumeIsolated {
                // Fensternummer erst hier lesen: Sie entsteht, wenn das Fenster erscheint.
                guard windowNumber == alert.window.windowNumber else { return false }
                stop(.alertFirstButtonReturn)
                return true
            }
            return consumed ? nil : event
        }
    }

    static let escapeKeyCode: UInt16 = 53

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
