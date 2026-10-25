import Foundation
@testable import QuillModel
import Testing
@testable import QuillFeatures

/// Bricht der Nutzer das Beenden nach „Wiederherstellen“ ab, wird die Vormerkung
/// zurückgenommen und gemeldet (ADR-019).
@MainActor
@Suite("Wiederherstellen: Beenden abgebrochen", .serialized)
struct RestoreQuitCancelledTests {
    let directory = URL.temporaryDirectory.appending(path: "QuillRestoreQuitTests-\(UUID().uuidString)")

    @Test func cancelledQuitWithdrawsRequest() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Store/Quill.store")
        let backup = StoreBackup(storeURL: storeURL, backupsURL: directory.appending(path: "Backups"))
        let persistence = QuillPersistence(container: try QuillStore.makeContainer(storeURL: storeURL), backup: backup)
        try await persistence.store.createPage(title: "Eins")
        let saved = try backup.createBackup(reason: .quit)
        let entry = try #require(try backup.entries().first { $0.url.lastPathComponent == saved.lastPathComponent })
        try await persistence.requestRestore(entry)
        #expect(backup.isRestorePending)

        var notes: [String] = []
        persistence.quitWasCancelled { title, _ in notes.append(title) }
        #expect(!backup.isRestorePending)
        #expect(backup.applyPendingRestore() == nil)
        #expect(notes == ["Restore Canceled"])

        // Ohne Vormerkung kein Hinweis.
        persistence.quitWasCancelled { title, _ in notes.append(title) }
        #expect(notes.count == 1)
    }
}
