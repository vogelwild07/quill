#if canImport(AppKit)
@testable import QuillFeatures
import Testing

/// Wert des Reglers „Liquid Glass“ für VoiceOver (ADR-036); XCUITest sieht nur die Zahl.
@MainActor
@Suite("Liquid Glass: Wert des Reglers")
struct GlassSettingsRowTests {
    @Test(arguments: [(0.0, "Clear"), (0.25, "25 % tinted"), (0.5, "50 % tinted"), (0.75, "75 % tinted"), (1.0, "Tinted")])
    func valueDescription(level: Double, expected: String) {
        #expect(GlassSettingsRow.valueDescription(level) == expected)
    }
}
#endif
