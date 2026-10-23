#if canImport(AppKit)
import SwiftUI

/// Einstellungen › Spotlight (15.2, ADR-033).
struct SpotlightSettingsView: View {
    let spotlight: SpotlightIndexing

    var body: some View {
        Form {
            Toggle(isOn: Binding(get: { spotlight.isEnabled }, set: { spotlight.setEnabled($0) })) {
                Text("Seiten in Spotlight zeigen", bundle: .module)
                Text("Titel und Text deiner Seiten kommen in den Suchindex dieses Macs, damit Spotlight sie findet. Seiten im Papierkorb nicht. Beim Ausschalten entfernt Quill alle Einträge.", bundle: .module)
            }
            .accessibilityIdentifier("settings.spotlight")
        }
        .formStyle(.grouped)
    }
}
#endif
