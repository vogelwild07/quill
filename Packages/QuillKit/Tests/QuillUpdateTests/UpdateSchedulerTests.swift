import Foundation
@testable import QuillUpdate
import Testing

/// „Schalter aus heißt keine Anfrage“ und höchstens einmal am Tag (ADR-037).
@MainActor
@Suite("Updates: Zeitplan")
struct UpdateSchedulerTests {
    final class Clock {
        var now = Date(timeIntervalSince1970: 2_000_000_000)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "QuillUpdateTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func switchedOffMeansNoRequest() {
        let settings = UpdateSettings()
        settings.configure(defaults: nil)
        let clock = Clock()
        var checks = 0
        let scheduler = UpdateScheduler(settings: settings, now: { clock.now }) { checks += 1 }
        for _ in 0..<30 {
            scheduler.tick()
            clock.now += 24 * 3600
        }
        #expect(checks == 0)
        #expect(settings.lastAttempt == nil, "Ohne Anfrage auch kein Versuch")
    }

    @Test func switchedOnChecksOnceADay() {
        let settings = UpdateSettings()
        settings.configure(defaults: nil, automaticChecks: true)
        let clock = Clock()
        var checks = 0
        let scheduler = UpdateScheduler(settings: settings, now: { clock.now }) { checks += 1 }
        scheduler.tick()
        #expect(checks == 1)
        for _ in 0..<23 {
            clock.now += 3600
            scheduler.tick()
        }
        #expect(checks == 1, "Stündlich geprüft, aber nur einmal am Tag gesucht")
        clock.now += 3600
        scheduler.tick()
        #expect(checks == 2)

        settings.setAutomaticChecks(false)
        clock.now += 48 * 3600
        scheduler.tick()
        #expect(checks == 2, "Ausgeschaltet: keine Anfrage mehr")
    }

    @Test func settingsAreStoredAndDefaultOff() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = UpdateSettings()
        settings.configure(defaults: defaults)
        #expect(!settings.automaticChecks, "Standard: aus")
        #expect(!settings.hasAsked)
        settings.answerFirstLaunchQuestion(automaticChecks: true)
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        settings.recordAttempt(date)
        settings.recordSuccess(date)

        let reloaded = UpdateSettings()
        reloaded.configure(defaults: defaults)
        #expect(reloaded.automaticChecks)
        #expect(reloaded.hasAsked)
        #expect(reloaded.lastAttempt == date)
        #expect(reloaded.lastSuccess == date)
    }

    @Test func memoryOnlyStoresNothing() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = UpdateSettings()
        settings.configure(defaults: nil, automaticChecks: true, hasAsked: false)
        settings.answerFirstLaunchQuestion(automaticChecks: false)
        settings.recordAttempt(.now)
        let reloaded = UpdateSettings()
        reloaded.configure(defaults: defaults)
        #expect(!reloaded.hasAsked)
        #expect(reloaded.lastAttempt == nil)
    }
}
