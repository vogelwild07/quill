#if canImport(AppKit)
import SwiftUI

/// Einstellungen › Zeitreise (12.4, ADR-031): wie lange gelöschte Bilder bleiben.
struct TimeTravelSettingsView: View {
    let retention: ImageRetentionSettings

    var body: some View {
        Form {
            Picker(selection: Binding(get: { retention.retention }, set: { retention.select($0) })) {
                ForEach(ImageRetention.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                Text("Gelöschte Bilder aufbewahren", bundle: .module)
                Text("Frühere Stände einer Seite enthalten keine Bilder, nur Verweise darauf. Ein Bild, das in keiner Seite mehr steht, bleibt so lange, damit die Zeitreise es zurückholen kann. Eine kürzere Frist wirkt ab dem nächsten Start.", bundle: .module)
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("settings.imageRetention")
        }
        .formStyle(.grouped)
    }
}
#endif
