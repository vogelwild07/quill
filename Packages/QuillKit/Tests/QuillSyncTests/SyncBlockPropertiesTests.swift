import Foundation
import QuillModel
@testable import QuillSync
import QuillTestFixtures
import Testing

/// Jedes Feld von `BlockProperties` übersteht den Sync (ADR-014): ins Seiten-Dokument,
/// als Datei zu einem anderen Gerät und wieder zurück auf den Standard. `PageDocument`
/// bildet die Felder einzeln ab; ein neues Feld ohne Abbildung schlägt hier fehl,
/// weil `SampleDocuments.fullProperties` jedes Feld setzt.
@Suite("Sync: alle Block-Felder")
struct SyncBlockPropertiesTests {
    static let full = SampleDocuments.fullProperties

    @Test func everyFieldSurvivesTheSync() throws {
        let block = BlockSnapshot(id: UUID(), kindRaw: BlockKind.todo.rawValue, text: "Aufgabe", properties: Self.full)
        let a = PageDocument()
        #expect(try a.update(to: [block]))
        // Gespeichert und neu geladen
        #expect(try PageDocument(bytes: a.save()).blocks().first?.properties == Self.full)

        // Zu einem anderen Gerät (ganzer Stand, wie die erste Datei im Ordner)
        let b = PageDocument()
        try b.apply(changes: a.save())
        #expect(try b.blocks().first?.properties == Self.full)

        // Zurück auf den Standard und wieder voll, jeweils beim anderen Gerät angekommen
        for properties in [BlockProperties(), Self.full] {
            var edited = block
            edited.properties = properties
            let version = b.version
            #expect(try b.update(to: [edited]))
            try a.apply(changes: b.changes(since: version))
            #expect(try a.blocks().first?.properties == properties)
        }
    }
}
