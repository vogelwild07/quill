#if canImport(AppKit)
import AppKit
import Testing
@testable import QuillFeatures

/// Fehler 1 aus dem Review: Beenden trotz Speicherfehler verlor Änderungen still.
@MainActor
@Suite("Beenden mit offenen Änderungen")
struct QuitGuardTests {
    struct SaveFailed: Error {}

    @Test func savedChangesTerminateWithoutAsking() async {
        var asked = false
        let terminate = await QuitGuard.shouldTerminate(flush: { nil }, confirm: { _ in asked = true; return false })
        #expect(terminate)
        #expect(!asked)
    }

    @Test(arguments: [false, true])
    func failedSaveAsksAndFollowsAnswer(_ quitAnyway: Bool) async {
        var asked = false
        let terminate = await QuitGuard.shouldTerminate(flush: { SaveFailed() }, confirm: { _ in asked = true; return quitAnyway })
        #expect(asked)
        #expect(terminate == quitAnyway)
    }

    @Test func alertDefaultsToCancel() {
        let alert = QuitGuard.makeAlert(for: SaveFailed())
        #expect(alert.messageText == "Änderungen konnten nicht gespeichert werden")
        #expect(alert.buttons.map(\.title) == ["Abbrechen", "Trotzdem beenden"])
        #expect(alert.buttons[0].keyEquivalent == "\r")
        #expect(alert.buttons[1].keyEquivalent.isEmpty)
        #expect(alert.buttons[1].hasDestructiveAction)
    }
}
#endif
