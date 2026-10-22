#if canImport(AppKit)
import QuillAI
import SwiftUI

/// Einstellungen › KI (16.1, ADR-032): einschalten oder erklären, warum es nicht geht.
struct AISettingsView: View {
    let ai: AISettings
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Form {
            if ai.availability == nil {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            } else if let reason = ai.availability.flatMap(Self.explanation) {
                // Ohne Modell kein Schalter: Ausgegraut wäre der Text zu blass.
                Label {
                    Text(reason)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.aiUnavailable")
            } else {
                Toggle(isOn: Binding(get: { ai.isEnabled }, set: { ai.setEnabled($0) })) {
                    Text("KI-Funktionen verwenden", bundle: .module)
                    Text("Das Sprachmodell von Apple Intelligence rechnet auf diesem Mac. Deine Notizen gehen dafür nicht ins Netz.", bundle: .module)
                }
                .accessibilityIdentifier("settings.aiEnabled")
            }
        }
        .formStyle(.grouped)
        .task { await ai.refresh() }
        .onChange(of: appearsActive) { if appearsActive { Task { await ai.refresh() } } }
    }

    static func explanation(_ availability: AIAvailability) -> String? {
        switch availability {
        case .available:
            nil
        case .deviceNotEligible:
            String(localized: "Dieser Mac unterstützt Apple Intelligence nicht. Die KI-Funktionen bleiben ausgeblendet.", bundle: .module)
        case .appleIntelligenceNotEnabled:
            String(localized: "Apple Intelligence ist aus. Schalte es in den Systemeinstellungen unter „Apple Intelligence & Siri“ ein, dann erscheinen die KI-Funktionen.", bundle: .module)
        case .modelNotReady:
            String(localized: "Das Sprachmodell wird noch geladen. Die KI-Funktionen erscheinen, sobald es bereit ist.", bundle: .module)
        case .unavailable:
            String(localized: "Das Sprachmodell steht gerade nicht bereit. Die KI-Funktionen bleiben ausgeblendet.", bundle: .module)
        }
    }
}
#endif
