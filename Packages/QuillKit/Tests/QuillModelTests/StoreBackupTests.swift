import Foundation
import SwiftData
import Testing
@testable import QuillModel

@Suite struct StoreBackupTests {
    let directory: URL
    let storeURL: URL

    init() {
        directory = URL.temporaryDirectory.appending(path: "QuillBackupTests-\(UUID().uuidString)")
        storeURL = directory.appending(path: "Store/Quill.store")
    }

    private func backup(at date: Date, version: String = "1.0.0") -> StoreBackup {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return StoreBackup(
            storeURL: storeURL,
            backupsURL: directory.appending(path: "Backups"),
            schemaVersion: version,
            calendar: calendar,
            now: { date }
        )
    }

    /// Store mit zwei Seiten und einem extern gespeicherten Bild anlegen; Container bleibt offen.
    private func makeStore() throws -> ModelContainer {
        let container = try QuillStore.makeContainer(storeURL: storeURL)
        let context = ModelContext(container)
        let page = Page(title: "Eins")
        context.insert(page)
        context.insert(Page(title: "Zwei"))
        let block = Block(kind: .image)
        block.page = page
        block.asset = Asset(data: Data(repeating: 7, count: 300_000))
        try context.save()
        return container
    }

    private func date(_ string: String) -> Date {
        try! Date(string, strategy: .iso8601)
    }

    @Test func backupOfOpenStoreContainsAllData() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeStore()

        let folder = try backup(at: .now).createBackup(reason: .launch)

        let restored = try QuillStore.makeContainer(storeURL: folder.appending(path: "Quill.store"))
        let context = ModelContext(restored)
        let titles = try context.fetch(FetchDescriptor<Page>()).map(\.title).sorted()
        #expect(titles == ["Eins", "Zwei"])
        let asset = try #require(try context.fetch(FetchDescriptor<Asset>()).first)
        #expect(asset.data?.count == 300_000)
        _ = container
    }

    @Test func noStoreMeansNoBackup() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try backup(at: .now).backupBeforeOpening() == nil)
        #expect(try backup(at: .now).backupOnQuitIfChanged() == nil)
    }

    @Test func launchBackupAtMostEvery24Hours() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try makeStore()
        try backup(at: .now).markOpened()
        let start = date("2026-10-18T08:00:00Z")

        #expect(try backup(at: start).backupBeforeOpening() != nil)
        #expect(try backup(at: start.addingTimeInterval(23 * 3600)).backupBeforeOpening() == nil)
        #expect(try backup(at: start.addingTimeInterval(25 * 3600)).backupBeforeOpening() != nil)
        #expect(try backup(at: .now).entries().count == 2)
    }

    @Test func versionChangeTriggersMigrationBackup() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try makeStore()
        try backup(at: .now, version: "1.0.0").markOpened()
        let now = date("2026-10-18T08:00:00Z")
        try backup(at: now).createBackup(reason: .launch)

        #expect(!backup(at: now, version: "1.0.0").isMigrationPending)
        #expect(backup(at: now, version: "2.0.0").isMigrationPending)
        let folder = try #require(try backup(at: now.addingTimeInterval(60), version: "2.0.0").backupBeforeOpening())

        #expect(folder.lastPathComponent.hasSuffix("_vor-migration-1.0.0-2.0.0"))
        #expect(try backup(at: now).entries().first?.isBeforeMigration == true)
    }

    @Test func missingVersionFileCountsAsMigration() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try makeStore()

        let folder = try #require(try backup(at: .now).backupBeforeOpening())

        #expect(folder.lastPathComponent.hasSuffix("_vor-migration-unbekannt-1.0.0"))
    }

    @Test func quitBackupOnlyAfterChanges() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeStore()
        let future = Date.now.addingTimeInterval(3600)
        try backup(at: future).createBackup(reason: .launch)

        #expect(try backup(at: future.addingTimeInterval(60)).backupOnQuitIfChanged() == nil)

        // Store nach dem letzten Backup ändern.
        let past = Date.now.addingTimeInterval(-3600)
        try FileManager.default.removeItem(at: directory.appending(path: "Backups"))
        try backup(at: past).createBackup(reason: .launch)
        let context = ModelContext(container)
        context.insert(Page(title: "Drei"))
        try context.save()

        #expect(try backup(at: .now).backupOnQuitIfChanged() != nil)
    }

    @Test func pruneKeepsSevenDaysFourWeeksAndMigrations() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try makeStore()
        let start = date("2026-08-01T10:00:00Z")
        // 60 Tage lang je zwei Backups pro Tag, dazu ein Migrations-Backup am Anfang.
        try backup(at: start).createBackup(reason: .beforeMigration(from: "1.0.0", to: "2.0.0"))
        for day in 0..<60 {
            let morning = start.addingTimeInterval(Double(day) * 86_400)
            try backup(at: morning).createBackup(reason: .launch)
            try backup(at: morning.addingTimeInterval(8 * 3600)).createBackup(reason: .quit)
        }

        try backup(at: .now).prune()

        let entries = try backup(at: .now).entries()
        let calendar = backup(at: .now).calendar
        let regular = entries.filter { !$0.isBeforeMigration }
        let days = Set(regular.map { calendar.dateComponents([.year, .month, .day], from: $0.date) })
        let weeks = Set(regular.map { calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.date) })

        #expect(entries.filter(\.isBeforeMigration).count == 1)
        // 7 Tages-Backups (23.–29.9., zwei ISO-Wochen) plus je das neueste der 4 Wochen davor (bis 30.8.).
        #expect(regular.count == 11)
        #expect(days.count == regular.count)
        #expect(weeks.count == 6)
        #expect(regular.map(\.date).last == start.addingTimeInterval(29 * 86_400 + 8 * 3600))
        #expect(regular.first?.date == start.addingTimeInterval(59 * 86_400 + 8 * 3600))
    }

    @Test func pruneRemovesPartialLeftovers() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let backups = directory.appending(path: "Backups")
        let partial = backups.appending(path: ".2026-10-18T08-00-00Z_start.partial")
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)

        try backup(at: .now).prune()

        #expect(!FileManager.default.fileExists(atPath: partial.path(percentEncoded: false)))
    }

    // MARK: Vor dem Leeren des Papierkorbs (ADR-017)

    @Test func backupBeforeEmptyingTrashAtMostHourly() throws {
        let container = try makeStore()
        defer { _ = container }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try #require(try backup(at: start).backupBeforeEmptyingTrash())
        #expect(first.lastPathComponent.hasSuffix("_vor-papierkorb-leeren"))
        #expect(try backup(at: start.addingTimeInterval(59 * 60)).backupBeforeEmptyingTrash() == nil)
        #expect(try backup(at: start.addingTimeInterval(61 * 60)).backupBeforeEmptyingTrash() != nil)
        #expect(try backup(at: start).entries().count == 2)
    }

    /// Ein späteres Backup am selben Tag verdrängt das vor dem Leeren nicht; nach
    /// 30 Tagen zählt es wie ein normales.
    @Test func trashBackupsSurvivePruningForThirtyDays() throws {
        let container = try makeStore()
        defer { _ = container }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let trash = try #require(try backup(at: start).backupBeforeEmptyingTrash())
        try backup(at: start.addingTimeInterval(3600)).createBackup(reason: .quit)
        try backup(at: start.addingTimeInterval(3600)).prune()
        #expect(FileManager.default.fileExists(atPath: trash.path(percentEncoded: false)))

        try backup(at: start.addingTimeInterval(31 * 24 * 3600)).prune()
        #expect(!FileManager.default.fileExists(atPath: trash.path(percentEncoded: false)))
    }
}
