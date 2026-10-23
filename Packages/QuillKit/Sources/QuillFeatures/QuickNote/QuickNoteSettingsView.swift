#if canImport(AppKit)
import SwiftUI

/// Einstellungen › Schnellnotiz (15.3, ADR-033).
struct QuickNoteSettingsView: View {
    let note: QuickNote

    var body: some View {
        Form {
            Toggle(isOn: Binding(get: { note.isEnabled }, set: { note.setEnabled($0) })) {
                Text("Schnellnotiz in der Menüleiste", bundle: .module)
                Text("Ein Symbol in der Menüleiste öffnet ein kleines Fenster für eine Notiz, ohne Quill nach vorn zu holen. Gesichert wird sie als neue Seite.", bundle: .module)
            }
            .accessibilityIdentifier("settings.quickNote")
            Toggle(isOn: Binding(get: { note.isShortcutEnabled }, set: { note.setShortcutEnabled($0) })) {
                Text("Kürzel ⌃⌥⌘N in allen Apps", bundle: .module)
                Text("Öffnet die Schnellnotiz auch, wenn eine andere App vorn ist. Andere Apps bekommen das Kürzel dann nicht.", bundle: .module)
            }
            .disabled(!note.isEnabled)
            .accessibilityIdentifier("settings.quickNoteShortcut")
            if note.wantsShortcut, note.isShortcutTaken {
                Text("Das Kürzel ist schon belegt, wohl von einer anderen App.", bundle: .module)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.quickNoteShortcutTaken")
            }
        }
        .formStyle(.grouped)
    }
}
#endif
