import Foundation
import Testing
@testable import QuillModel

/// Vormerkung und Markierung beim Wiederherstellen (ADR-019) liegen als JSON auf der
/// Platte; eine ältere Version kann sie geschrieben haben. Mit `BackupName` muss das
/// Format gleich bleiben: der Name als einfacher String.
@Suite("Backup-Name auf der Platte")
struct BackupNameTests {
    let name = "2026-10-19T10-15-00_beenden-2"

    @Test func readsRequestWrittenBeforeTheType() throws {
        let old = Data(#"{"backup":"2026-10-19T10-15-00_beenden-2"}"#.utf8)
        let request = try JSONDecoder().decode(StoreBackup.RestoreRequest.self, from: old)
        #expect(request.backup == BackupName(name))
    }

    @Test func writesRequestAsBefore() throws {
        let data = try JSONEncoder().encode(StoreBackup.RestoreRequest(backup: BackupName(name)))
        #expect(String(decoding: data, as: UTF8.self) == #"{"backup":"2026-10-19T10-15-00_beenden-2"}"#)
    }

    @Test func readsTagWrittenBeforeTheType() throws {
        let old = Data(#"{"backup":"a_start","safety":"b_vor-wiederherstellen"}"#.utf8)
        let tag = try JSONDecoder().decode(StoreBackup.RestoreTag.self, from: old)
        #expect(tag.backup == BackupName("a_start"))
        #expect(tag.safety == BackupName("b_vor-wiederherstellen"))

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(tag), as: UTF8.self) == #"{"backup":"a_start","safety":"b_vor-wiederherstellen"}"#)
    }
}
