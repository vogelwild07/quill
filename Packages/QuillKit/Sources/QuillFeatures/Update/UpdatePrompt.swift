#if canImport(AppKit)
import AppKit

/// Einmalige Frage beim ersten Start (ADR-037): Soll Quill selbst nach Updates suchen?
/// Standard (Return, Escape) ist „Nicht suchen“.
@MainActor
enum UpdatePrompt {
    static let noIdentifier = "updatePrompt.no"
    static let yesIdentifier = "updatePrompt.yes"

    /// `true`: einmal am Tag automatisch suchen.
    static func ask() -> Bool {
        let alert = makeAlert()
        alert.layout()
        let escape = MigrationPrompt.escapeHandler(for: alert) { NSApp.stopModal(withCode: $0) }
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: escape)
        defer { monitor.map(NSEvent.removeMonitor) }
        NSApp.activate()
        return automaticChecks(for: alert.runModal())
    }

    static func automaticChecks(for response: NSApplication.ModalResponse) -> Bool {
        response == .alertSecondButtonReturn
    }

    static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = String(localized: "Automatisch nach Updates suchen?", bundle: .module)
        alert.informativeText = String(
            localized: "Quill fragt dann höchstens einmal am Tag die Liste der Versionen bei GitHub ab, ohne Angaben über dich oder deinen Mac. Installiert wird nur, wenn du zustimmst. Du kannst das jederzeit unter Einstellungen › Allgemein ändern.",
            bundle: .module
        )
        let no = alert.addButton(withTitle: String(localized: "Nicht suchen", bundle: .module))
        no.keyEquivalent = "\r"
        no.setAccessibilityIdentifier(noIdentifier)
        let yes = alert.addButton(withTitle: String(localized: "Automatisch suchen", bundle: .module))
        yes.keyEquivalent = ""
        yes.setAccessibilityIdentifier(yesIdentifier)
        return alert
    }
}
#endif
