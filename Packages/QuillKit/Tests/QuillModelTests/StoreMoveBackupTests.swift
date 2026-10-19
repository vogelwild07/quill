import Foundation
import SwiftData
import Testing
@testable import QuillModel

extension DiskStoreSuites {
    /// Umzug in einen neuen Container nach dem Wechsel der Bundle-ID (ADR-022,
    /// `docs/data-model.md`): Ein Backup aus dem alten Container wird in den neuen
    /// kopiert und über „Backup wiederherstellen“ eingespielt. Der neue Container hat
    /// dann schon ein jüngeres Backup vom selben Tag (Beenden nach dem ersten Start).
    @Suite(.serialized) struct StoreMoveBackupTests {
        let oldDirectory: URL
        let newDirectory: URL

        static let start = ISO8601DateFormatter().date(from: "2026-10-19T10:00:00Z")!
        static let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar
        }()

        init() {
            let base = URL.temporaryDirectory.appending(path: "QuillMoveTests-\(UUID().uuidString)")
            oldDirectory = base.appending(path: "alt")
            newDirectory = base.appending(path: "neu")
        }

        private func backup(in directory: URL, minutes: Double) -> StoreBackup {
            let date = Self.start.addingTimeInterval(minutes * 60)
            return StoreBackup(
                storeURL: directory.appending(path: "Store/Quill.store"),
                backupsURL: directory.appending(path: "Backups"),
                calendar: Self.calendar, now: { date }
            )
        }

        private func titles(in directory: URL) throws -> [String] {
            let container = try QuillStore.makeContainer(storeURL: directory.appending(path: "Store/Quill.store"))
            return try ModelContext(container).fetch(FetchDescriptor<Page>()).map(\.title).sorted()
        }

        /// Schritte 1 bis 5 der Anleitung; `slug` ist die Endung des kopierten Ordners.
        /// Gibt den neuen Container nach dem Start und den Ort der Kopie zurück.
        private func moveBackup(renamingTo slug: String) throws -> (backup: StoreBackup, copy: URL) {
            // 1. Alter Container: Stand „Alt“, beim Beenden entsteht das Backup.
            let container = try QuillStore.makeContainer(storeURL: oldDirectory.appending(path: "Store/Quill.store"))
            let context = ModelContext(container)
            context.insert(Page(title: "Alt"))
            try context.save()
            let saved = try backup(in: oldDirectory, minutes: 0).createBackup(reason: .quit)

            // 3. Neuer Container: erster Start legt einen leeren Store an, Beenden ein Backup.
            _ = try QuillStore.makeContainer(storeURL: newDirectory.appending(path: "Store/Quill.store"))
            #expect(try backup(in: newDirectory, minutes: 5).backupOnQuitIfChanged() != nil)

            // 4. Kopie des alten Backups, als Ganzes, mit neuer Endung.
            let name = saved.lastPathComponent.replacingOccurrences(of: "_beenden", with: "_\(slug)")
            let copy = newDirectory.appending(path: "Backups/\(name)")
            try FileManager.default.copyItem(at: saved, to: copy)

            // 5. Start der neuen Quill: Backup beim Start und Aufräumen.
            let started = backup(in: newDirectory, minutes: 10)
            try started.backupBeforeOpening()
            return (started, copy)
        }

        @Test func renamedBackupSurvivesStartAndRestores() throws {
            let (backup, copy) = try moveBackup(renamingTo: "vor-umzug")
            let entry = try #require(try backup.entries().first { $0.url.lastPathComponent == copy.lastPathComponent })
            #expect(entry.kind == .beforeMove)

            try backup.requestRestore(entry)
            guard case .restored = backup.applyPendingRestore() else {
                Issue.record("Nicht wiederhergestellt")
                return
            }
            #expect(try titles(in: newDirectory) == ["Alt"])
        }

        /// Warum die Anleitung umbenennt: Ein Backup „Beim Beenden“ vom selben Tag ist
        /// älter als das des neuen Containers und wird beim Start aufgeräumt.
        @Test func copiedQuitBackupIsRemovedOnStart() throws {
            let (_, copy) = try moveBackup(renamingTo: "beenden")
            #expect(!FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
        }
    }
}
