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

    @Test func onByDefaultAndTheChoiceIsKept() async throws {
        let defaults = try Self.defaults()
        let ai = AISettings(defaults: defaults, model: SilentModel(), availability: { .available })
        await ai.refresh()
        #expect(ai.isEnabled)
        #expect(ai.isUsable)
        ai.setEnabled(false)
        #expect(!ai.isUsable)
        #expect(AISettings(defaults: defaults, model: SilentModel(), availability: { .available }).isEnabled == false)
    }

    @Test func withoutTheModelNothingIsUsable() async {
        for reason in AIAvailability.allCases where reason != .available {
            let ai = AISettings(defaults: nil, model: SilentModel(), availability: { reason })
            await ai.refresh()
            #expect(ai.isEnabled)
            #expect(!ai.isUsable, "\(reason)")
        }
    }

    /// Geprüft wird außerhalb des Main Threads (16.2): Bis dahin ist nichts verwendbar.
    @Test func availabilityIsCheckedOffTheMainThread() async {
        let ai = AISettings(defaults: nil, model: SilentModel(), availability: {
            Thread.isMainThread ? .unavailable : .available
        })
        #expect(ai.availability == nil)
        #expect(!ai.isUsable)
        await ai.refresh()
        #expect(ai.availability == .available)
    }

    @Test func refreshNoticesAModelThatBecameReady() async {
        final class Current: @unchecked Sendable { var value = AIAvailability.modelNotReady }
        let current = Current()
        let ai = AISettings(defaults: nil, model: SilentModel(), availability: { current.value })
        await ai.refresh()
        #expect(!ai.isUsable)
        current.value = .available
        await ai.refresh()
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
