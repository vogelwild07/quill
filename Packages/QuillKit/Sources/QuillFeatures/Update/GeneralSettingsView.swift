#if canImport(AppKit)
import QuillUpdate
import SwiftUI

/// Einstellungen › Allgemein: Updates (ADR-037). Standard aus.
struct GeneralSettingsView: View {
    let updates: AppUpdates

    private var settings: UpdateSettings { updates.settings }

    var body: some View {
        Form {
            Toggle(isOn: Binding(get: { settings.automaticChecks }, set: { updates.setAutomaticChecks($0) })) {
                Text("Automatisch suchen", bundle: .module)
                Text("Höchstens einmal am Tag fragt Quill die Liste der Versionen bei GitHub ab, ohne Angaben über dich oder deinen Mac. Installiert wird nur, wenn du zustimmst; vorher legt Quill ein Backup an. Von Hand: Quill › Nach Updates suchen …", bundle: .module)
            }
            .accessibilityIdentifier("settings.updates.automatic")
            LabeledContent(String(localized: "Zuletzt geprüft", bundle: .module)) {
                Text(lastChecked)
                    .accessibilityIdentifier("settings.updates.lastChecked")
            }
        }
        .formStyle(.grouped)
    }

    private var lastChecked: String {
        settings.lastSuccess?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Noch nie", bundle: .module)
    }
}
#endif
