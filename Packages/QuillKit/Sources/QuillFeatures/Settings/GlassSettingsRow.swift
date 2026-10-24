#if canImport(AppKit)
import AppKit
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

            HStack(spacing: 8) {
                // Die Symbole sagen dasselbe wie der Wert des Reglers („Klar“ … „Getönt“).
                Image(systemName: "circle.dotted")
                    .accessibilityHidden(true)
                    .help(String(localized: "Klar", bundle: .module))
                GlassLevelSlider(
                    level: Binding(get: { glass.level }, set: { glass.setLevel($0) }),
                    label: String(localized: "Liquid Glass", bundle: .module),
                    valueDescription: Self.valueDescription(glass.level)
                )
                .disabled(isSliderDisabled)
                Image(systemName: "circle.fill")
                    .accessibilityHidden(true)
                    .help(String(localized: "Getönt", bundle: .module))
            }
            .foregroundStyle(isSliderDisabled ? .tertiary : .secondary)
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

/// Regler mit fünf Rasterpunkten als `NSSlider`: Der `Slider` von SwiftUI gibt VoiceOver
/// nur die Zahl (0,25) statt „25 % getönt“, und sein Knopf erscheint als eigenes Element
/// ohne Beschreibung (Meldung im Audit). Der Knopf ist hier kein eigenes Element; bedient
/// wird der Regler selbst, mit den Pfeiltasten oder VoiceOver.
private struct GlassLevelSlider: NSViewRepresentable {
    @Binding var level: Double
    let label: String
    let valueDescription: String

    func makeNSView(context: Context) -> NSSlider {
        let slider = GlassNSSlider(value: level, minValue: 0, maxValue: 1, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.numberOfTickMarks = Int(1 / GlassSettings.step) + 1
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.controlSize = .regular
        slider.setAccessibilityIdentifier("settings.glass.slider")
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.level = $level
        if slider.doubleValue != level { slider.doubleValue = level }
        slider.isEnabled = context.environment.isEnabled
        slider.setAccessibilityLabel(label)
        slider.setAccessibilityValueDescription(valueDescription)
    }

    func makeCoordinator() -> Coordinator { Coordinator(level: $level) }

    @MainActor
    final class Coordinator: NSObject {
        var level: Binding<Double>

        init(level: Binding<Double>) {
            self.level = level
        }

        @objc func changed(_ sender: NSSlider) {
            level.wrappedValue = sender.doubleValue
        }
    }
}

/// Ohne den Knopf als eigenes Element; das Element der Bedienungshilfen ist die Zelle.
private final class GlassNSSlider: NSSlider {
    override class var cellClass: AnyClass? {
        get { GlassSliderCell.self }
        set {}
    }
}

private final class GlassSliderCell: NSSliderCell {
    override func accessibilityChildren() -> [Any]? { [] }
}
#endif
