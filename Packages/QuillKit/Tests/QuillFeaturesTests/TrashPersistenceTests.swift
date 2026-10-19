import Foundation
import QuillModel
import SwiftData
import Testing
@testable import QuillFeatures

/// Endgültig löschen und Auto-Leeren mit Backup davor (ADR-017), gegen einen Store im
/// Temp-Ordner, nie den echten.
@MainActor
@Suite("Papierkorb: Löschen mit Backup", .serialized)
struct TrashPersistenceTests {
    let directory = URL.temporaryDirectory.appending(path: "QuillTrashTests-\(UUID().uuidString)")

    private func make(backupsAt backups: URL? = nil) throws -> QuillPersistence {
        let storeURL = directory.appending(path: "Store/Quill.store")
        let container = try QuillStore.makeContainer(storeURL: storeURL)
        let backup = StoreBackup(storeURL: storeURL, backupsURL: backups ?? directory.appending(path: "Backups"))
        return QuillPersistence(container: container, backup: backup)
    }

    private func backups() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "Backups").path)) ?? []
    }

    private func titles(_ persistence: QuillPersistence) throws -> [String] {
        try ModelContext(persistence.container).fetch(FetchDescriptor<Page>()).map(\.title).sorted()
    }

    @Test func deletePermanentlyBacksUpFirst() async throws {
        let persistence = try make()
        let id = try await persistence.store.createPage(title: "Weg")
        try await persistence.store.createPage(title: "Bleibt")
        try await persistence.store.trash(id)

        try await persistence.deletePermanently([id])
        #expect(try titles(persistence) == ["Bleibt"])
        #expect(backups().contains { $0.hasSuffix("_vor-papierkorb-leeren") })
    }

    @Test func failedBackupDeletesNothing() async throws {
        let blocker = directory.appending(path: "KeinOrdner")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("Datei statt Ordner".utf8).write(to: blocker)
        let persistence = try make(backupsAt: blocker)
        let id = try await persistence.store.createPage(title: "Bleibt")
        try await persistence.store.trash(id)

        await #expect(throws: (any Error).self) { try await persistence.deletePermanently([id]) }
        await #expect(throws: (any Error).self) { try await persistence.emptyTrash() }
        await persistence.emptyExpiredTrash(now: .now.addingTimeInterval(QuillPersistence.trashRetention + 60))
        #expect(try titles(persistence) == ["Bleibt"])
    }

    @Test func autoEmptyOnlyBacksUpWhenSomethingIsDue() async throws {
        let persistence = try make()
        let id = try await persistence.store.createPage(title: "Alt")
        try await persistence.store.trash(id)

        await persistence.emptyExpiredTrash(now: .now.addingTimeInterval(29 * 24 * 3600))
        #expect(try titles(persistence) == ["Alt"])
        #expect(backups().isEmpty)

        await persistence.emptyExpiredTrash(now: .now.addingTimeInterval(QuillPersistence.trashRetention + 60))
        #expect(try titles(persistence).isEmpty)
        #expect(backups().count == 1)
    }
}
