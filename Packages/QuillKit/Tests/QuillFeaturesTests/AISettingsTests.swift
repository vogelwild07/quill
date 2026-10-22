import Foundation
import QuillAI
@testable import QuillFeatures
import Testing

/// Einstellungen › KI (16.1, ADR-032), ohne das echte Modell.
@MainActor
@Suite("KI: Einstellungen")
struct AISettingsTests {
    struct SilentModel: TextModel {
        func respond(instructions: String, prompt: String) async throws -> String { "" }
    }

    static func defaults() throws -> UserDefaults {
        let name = "AISettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func onByDefaultAndTheChoiceIsKept() throws {
        let defaults = try Self.defaults()
        let ai = AISettings(defaults: defaults, model: SilentModel(), availability: { .available })
        #expect(ai.isEnabled)
        #expect(ai.isUsable)
        ai.setEnabled(false)
        #expect(!ai.isUsable)
        #expect(AISettings(defaults: defaults, model: SilentModel(), availability: { .available }).isEnabled == false)
    }

    @Test func withoutTheModelNothingIsUsable() {
        for reason in AIAvailability.allCases where reason != .available {
            let ai = AISettings(defaults: nil, model: SilentModel(), availability: { reason })
            #expect(ai.isEnabled)
            #expect(!ai.isUsable, "\(reason)")
        }
    }

    @Test func refreshNoticesAModelThatBecameReady() {
        final class Current { var value = AIAvailability.modelNotReady }
        let current = Current()
        let ai = AISettings(defaults: nil, model: SilentModel(), availability: { current.value })
        #expect(!ai.isUsable)
        current.value = .available
        ai.refresh()
        #expect(ai.isUsable)
    }

    #if canImport(AppKit)
    @Test func everyReasonIsExplained() {
        #expect(AISettingsView.explanation(.available) == nil)
        for reason in AIAvailability.allCases where reason != .available {
            #expect(AISettingsView.explanation(reason)?.isEmpty == false, "\(reason)")
        }
    }
    #endif
}
