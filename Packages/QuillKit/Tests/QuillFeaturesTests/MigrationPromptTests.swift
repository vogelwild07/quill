import AppKit
import CryptoKit
import Foundation
@testable import QuillModel
import SwiftData
import Testing
@testable import QuillFeatures

/// Rückfrage vor der Migration auf ein neues Schema (Phase 11.2, ADR-029). Alle Stores
/// liegen im temporären Ordner (`-QuillStoreDirectory`), nie der echte.
@MainActor
@Suite("Migration: Rückfrage, Backup, Rückweg", .serialized)
struct MigrationPromptTests {
    let name = "QuillMigrationPromptTests-\(UUID().uuidString)"
    var directory: URL { FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory) }
    var storeFolder: URL { directory.appending(path: "Store", directoryHint: .isDirectory) }
    var backupsFolder: URL { directory.appending(path: "Backups", directoryHint: .isDirectory) }

    /// Test-Store mit V1-Bestand, mit Rückfrage wie beim echten Store.
    var arguments: [String] {
        ["Quill", "-QuillStoreDirectory", name, "-QuillSeedSchemaV1", "YES", "-QuillAskBeforeMigration", "YES"]
    }

    /// Prüfsumme aller Dateien im Ordner, mit relativem Pfad.
    static func fingerprint(_ folder: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        let base = folder.path(percentEncoded: false)
        let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in enumerator where (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
            let data = try Data(contentsOf: url)
            result[String(url.path(percentEncoded: false).dropFirst(base.count))] = SHA256.hash(data: data).description
        }
        return result
    }

    func backupNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: backupsFolder.path(percentEncoded: false))) ?? [])
            .filter { !$0.hasPrefix(".") }
    }

    func titles(_ persistence: QuillPersistence) throws -> Set<String> {
        Set(try ModelContext(persistence.container).fetch(FetchDescriptor<Page>()).map(\.title))
    }

    @Test func realStoreAlwaysAsksTestStoresOnlyOnRequest() {
        #expect(QuillPersistence.asksBeforeMigration(nil, arguments: ["Quill"]))
        #expect(!QuillPersistence.asksBeforeMigration(.inMemory, arguments: ["Quill"]))
        #expect(!QuillPersistence.asksBeforeMigration(.directory("x"), arguments: ["Quill"]))
        #expect(QuillPersistence.asksBeforeMigration(.directory("x"), arguments: ["Quill", "-QuillAskBeforeMigration", "YES"]))
        #expect(!QuillPersistence.asksBeforeMigration(.inMemory, arguments: ["Quill", "-QuillAskBeforeMigration", "YES"]))
        #expect(!QuillPersistence.asksBeforeMigration(.directory("x"), arguments: ["Quill", "-QuillAskBeforeMigration", "NO"]))
    }

    @Test func quitIsTheDefaultAndMigrateNeedsAClick() throws {
        let alert = MigrationPrompt.makeAlert()
        #expect(alert.buttons.map { $0.accessibilityIdentifier() } == ["migration.quit", "migration.migrate"])
        #expect(alert.buttons.map(\.title) == ["Beenden", "Umstellen"])
        // Return löst „Beenden“ aus; „Umstellen“ hat weder Return noch Escape.
        #expect(alert.buttons[0].keyEquivalent == "\r")
        #expect(alert.buttons[1].keyEquivalent.isEmpty)
        #expect(alert.alertStyle == .warning)
    }

    @Test func declineLeavesTheStoreUntouched() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        // Bestand anlegen, ohne zu öffnen (Seed ist Teil von `open`): erster Lauf lehnt ab.
        var asked: [(String?, String)] = []
        #expect(throws: QuillPersistence.OpenError.migrationDeclined) {
            try QuillPersistence.open(arguments: arguments) { from, to in
                asked.append((from, to))
                return .quit
            }
        }
        #expect(asked.count == 1)
        #expect(asked.first?.0 == "1.0.0")
        #expect(asked.first?.1 == QuillStore.schemaVersion)
        let before = try Self.fingerprint(storeFolder)
        #expect(!before.isEmpty)
        // Zweites Ablehnen: weiterhin byte-gleich, kein Backup.
        #expect(throws: QuillPersistence.OpenError.migrationDeclined) {
            try QuillPersistence.open(arguments: arguments) { _, _ in .quit }
        }
        #expect(try Self.fingerprint(storeFolder) == before)
        #expect(backupNames().isEmpty)
    }

    @Test func confirmBacksUpAndMigrates() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = try QuillPersistence.open(arguments: arguments) { _, _ in .migrate }
        #expect(try titles(persistence) == [SchemaV1Seed.rootTitle, SchemaV1Seed.childTitle])
        let pages = try ModelContext(persistence.container).fetch(FetchDescriptor<Page>())
        #expect(pages.allSatisfy { $0.syncDocument == nil && !$0.isRestored })
        #expect(backupNames().contains { $0.hasSuffix("_vor-migration-1.0.0-\(QuillStore.schemaVersion)") })
        // Danach keine Rückfrage mehr.
        var askedAgain = false
        _ = try QuillPersistence.open(arguments: arguments) { _, _ in
            askedAgain = true
            return .migrate
        }
        #expect(!askedAgain)
    }

    @Test func laterChangesNothingAndAsksAgain() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: QuillPersistence.OpenError.migrationDeferred) {
            try QuillPersistence.open(arguments: arguments) { _, _ in .later }
        }
        let before = try Self.fingerprint(storeFolder)
        #expect(throws: QuillPersistence.OpenError.migrationDeferred) {
            try QuillPersistence.open(arguments: arguments) { _, _ in .later }
        }
        #expect(try Self.fingerprint(storeFolder) == before)
        #expect(backupNames().isEmpty)
        let persistence = try QuillPersistence.open(arguments: arguments) { _, _ in .migrate }
        #expect(try titles(persistence).count == 2)
    }

    @Test func testStoresWithoutTheFlagMigrateWithoutAsking() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        var asked = false
        let persistence = try QuillPersistence.open(arguments: ["Quill", "-QuillStoreDirectory", name, "-QuillSeedSchemaV1", "YES"]) { _, _ in
            asked = true
            return .quit
        }
        #expect(!asked)
        #expect(try titles(persistence).count == 2)
    }

    @Test func wayBackRestoresV1AndDeclineKeepsIt() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = try QuillPersistence.open(arguments: arguments) { _, _ in .migrate }
        try await persistence.store.createPage(title: "Nur in V2")
        let entries = try await persistence.backupEntries()
        let beforeMigration = try #require(entries.first { $0.entry.url.lastPathComponent.contains("_vor-migration-1.0.0-") })
        try await persistence.requestRestore(beforeMigration.entry)

        // Neustart: Das Backup wird eingespielt, dann fragt Quill wieder; „Beenden“.
        var asked = false
        #expect(throws: QuillPersistence.OpenError.migrationDeclined) {
            try QuillPersistence.open(arguments: arguments) { from, _ in
                asked = from == "1.0.0" || from == nil
                return .quit
            }
        }
        #expect(asked)
        // Der Store ist wieder V1 mit dem Stand vor der Migration, lesbar für eine ältere Version.
        let schema = Schema(versionedSchema: SchemaV1.self)
        let v1 = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema, url: storeFolder.appending(path: "Quill.store"), allowsSave: false, cloudKitDatabase: .none
            )
        )
        let titles = Set(try ModelContext(v1).fetch(FetchDescriptor<SchemaV1.Page>()).map(\.title))
        #expect(titles == [SchemaV1Seed.rootTitle, SchemaV1Seed.childTitle])
        // Der V2-Stand liegt beiseite, nicht gelöscht (ADR-019).
        #expect(backupNames().contains { $0.contains("vor-wiederherstellen") })
    }
}
