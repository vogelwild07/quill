import QuillDesign
import QuillEditor
import QuillEditorCore
import SwiftUI

/// Zeile „Liquid Glass“ unter Einstellungen › Darstellung (ADR-036): „Wie System“ und
/// darunter der Regler zwischen klar und getönt, aufgebaut wie in den Systemeinstellungen.
/// Ausgegraut bei „Wie System“ und bei „Transparenz reduzieren“, dann mit Hinweis.
struct GlassSettingsRow: View {
    private var glass = GlassSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Liquid Glass", bundle: .module)
                .accessibilityAddTraits(.isHeader)
            Toggle(isOn: Binding(get: { glass.followsSystem }, set: { glass.setFollowsSystem($0) })) {
                Text("Wie System", bundle: .module)
                Text("Quill folgt der Einstellung für Liquid Glass in den Systemeinstellungen.", bundle: .module)
            }
            .accessibilityIdentifier("settings.glass.followsSystem")

            Slider(value: Binding(get: { glass.level }, set: { glass.setLevel($0) }), in: 0...1, step: GlassSettings.step) {
                Text("Liquid Glass", bundle: .module)
            } minimumValueLabel: {
                Image(systemName: "circle.dotted")
                    .accessibilityLabel(Text("Klar", bundle: .module))
                    .help(String(localized: "Klar", bundle: .module))
            } maximumValueLabel: {
                Image(systemName: "circle.fill")
                    .accessibilityLabel(Text("Getönt", bundle: .module))
                    .help(String(localized: "Getönt", bundle: .module))
            }
            .labelsHidden()
            .disabled(isSliderDisabled)
            .accessibilityValue(Self.valueDescription(glass.level))
            .accessibilityIdentifier("settings.glass.slider")
            .frame(maxWidth: QuillDesign.Glass.sliderWidth)

            if glass.reduceTransparency {
                Label {
                    Text("„Transparenz reduzieren“ ist in den Bedienungshilfen an. Das Glas in Quill ist deshalb deckend.", bundle: .module)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.glass.reduceTransparency")
            }
        }
    }

    private var isSliderDisabled: Bool { glass.followsSystem || glass.reduceTransparency }

    /// Wert für VoiceOver: „Klar“, „Getönt“ oder dazwischen in Prozent.
    static func valueDescription(_ level: Double) -> String {
        switch level {
        case ...0: String(localized: "Klar", bundle: .module)
        case 1...: String(localized: "Getönt", bundle: .module)
        default: String(localized: "\(Int((level * 100).rounded())) % getönt", bundle: .module)
        }
    }
}
