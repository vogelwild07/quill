import Foundation
@testable import QuillUpdate
import Testing

/// Ablauf im Fenster „Update“: Backup vor „installieren“ (ADR-037).
@MainActor
@Suite("Updates: Ablauf")
struct UpdateModelTests {
    struct BackupFailed: Error {}

    final class Log {
        var entries: [String] = []
    }

    let offer = UpdateModel.Offer(version: "0.5.0", notes: "Neu: Updates")

    /// Wartet, bis das Fenster das Angebot zeigt.
    private func waitForOffer(_ model: UpdateModel) async {
        while model.phase != .found(offer) { await Task.yield() }
    }

    @Test func installOnlyAfterTheBackup() async {
        let model = UpdateModel()
        let log = Log()
        let task = Task { await model.offer(offer) { log.entries.append("backup") } }
        await waitForOffer(model)
        #expect(model.isPresented)
        #expect(log.entries.isEmpty, "Kein Backup ohne Wahl")
        model.choose(.install)
        let decision = await task.value
        #expect(decision == .install)
        #expect(log.entries == ["backup"])
    }

    @Test func failedBackupInstallsNothingAndStaysVisible() async {
        let model = UpdateModel()
        let task = Task { await model.offer(offer) { throw BackupFailed() } }
        await waitForOffer(model)
        model.choose(.install)
        #expect(await task.value == .dismiss)
        #expect(model.phase == .failed(.backupFailed))
        model.dismissedBySparkle()
        #expect(model.isPresented, "Der Fehler bleibt, bis der Nutzer ihn schließt")
        model.close()
        #expect(!model.isPresented)
    }

    @Test func laterAndSkipNeverBackUp() async {
        for (choice, expected) in [(UpdateModel.Choice.later, UpdateModel.Decision.dismiss), (.skip, .skip)] {
            let model = UpdateModel()
            let log = Log()
            let task = Task { await model.offer(offer) { log.entries.append("backup") } }
            await waitForOffer(model)
            model.choose(choice)
            #expect(await task.value == expected)
            #expect(log.entries.isEmpty)
            #expect(!model.isPresented)
        }
    }

    @Test func closingTheWindowMeansLater() async {
        let model = UpdateModel()
        let task = Task { await model.offer(offer) {} }
        await waitForOffer(model)
        model.close()
        #expect(await task.value == .dismiss)
        #expect(!model.isPresented)
    }

    @Test func backgroundErrorsStaySilent() {
        let model = UpdateModel()
        var acknowledged = false
        model.failed(.network) { acknowledged = true }
        #expect(acknowledged)
        #expect(!model.isPresented)
    }

    @Test func userInitiatedCheckShowsResultUntilClosed() {
        let model = UpdateModel()
        var cancelled = false
        var acknowledged = false
        model.beginUserInitiatedCheck { cancelled = true }
        #expect(model.phase == .checking)
        #expect(model.canCancel)
        model.noUpdate { acknowledged = true }
        #expect(model.phase == .upToDate)
        #expect(!acknowledged)
        model.close()
        #expect(acknowledged)
        #expect(!cancelled, "Suche war schon fertig")
        #expect(!model.isPresented)
    }

    @Test func quitCancelledOffersRetry() {
        let model = UpdateModel()
        var retried = false
        model.bringToFront()
        model.installing(applicationTerminated: false) { retried = true }
        #expect(model.phase == .failed(.couldNotQuit))
        #expect(model.canRetry)
        model.retry()
        #expect(retried)
        #expect(model.phase == .installing)
    }
}
