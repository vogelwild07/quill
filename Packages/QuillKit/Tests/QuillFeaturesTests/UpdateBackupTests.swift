import Foundation
@testable import QuillFeatures
import QuillModel
import Testing

/// Backup vor einem Update (ADR-037): der Rückweg, bevor Sparkle die neue Version
/// installiert. Store nur im temporären Ordner.
@MainActor
@Suite("Update: Backup vorher", .serialized)
final class UpdateBackupTests {
    let name = "QuillUpdateBackupTests-\(UUID().uuidString)"
    let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func backupBeforeUpdateKeepsTheStoreAndNamesTheVersion() async throws {
        var persistence: QuillPersistence? = try QuillPersistence.open(arguments: ["Quill", "-QuillStoreDirectory", name]) { _, _ in .migrate }
        try await persistence!.store.createPage(title: "Vor dem Update")
        let folder = try #require(try await persistence!.backupBeforeUpdate(to: "0.5.0"))
        #expect(folder.lastPathComponent.contains("vor-update-0.5.0"))
        let entry = try #require(try await persistence!.backupEntries().first { $0.entry.kind == .beforeUpdate })

        // Einspielen bringt den Stand von vorher zurück.
        try await persistence!.store.createPage(title: "Nach dem Update")
        try await persistence!.requestRestore(entry.entry)
        persistence = nil
        let restored = try QuillPersistence.open(arguments: ["Quill", "-QuillStoreDirectory", name]) { _, _ in .migrate }
        #expect(try await restored.store.pageSnapshots().map(\.title) == ["Vor dem Update"])
    }

    @Test func storeInMemoryHasNoBackup() async throws {
        let persistence = try QuillPersistence.open(arguments: ["Quill", "-QuillInMemoryStore", "YES"]) { _, _ in .migrate }
        #expect(try await persistence.backupBeforeUpdate(to: "0.5.0") == nil)
    }
}
