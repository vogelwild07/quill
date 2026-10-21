import Automerge
import Foundation
import QuillModel
import Testing
@testable import QuillSync

@Suite("Seiten-Dokument: Blöcke ↔ Automerge")
struct PageDocumentTests {
    static func rich(_ runs: RichText.Run...) throws -> Data { try RichText(runs: runs).encoded() }

    static func sample() throws -> [BlockSnapshot] {
        [
            BlockSnapshot(id: UUID(), kindRaw: BlockKind.heading1.rawValue, text: "Einkauf 🇩🇪"),
            BlockSnapshot(
                id: UUID(), text: "Milch 🥛 und Brot",
                richText: try rich(
                    .init(text: "Milch 🥛 "), .init(text: "und", marks: ["bold", "italic"]),
                    .init(text: " Brot", link: "https://example.org")
                )
            ),
            BlockSnapshot(
                id: UUID(), kindRaw: BlockKind.todo.rawValue, text: "Eier",
                properties: BlockProperties(indent: 2, isChecked: true, isRestored: true)
            ),
            BlockSnapshot(
                id: UUID(), kindRaw: BlockKind.code.rawValue, text: "let a = 1\nlet b = 2",
                properties: BlockProperties(codeLanguage: "swift")
            ),
            BlockSnapshot(id: UUID(), kindRaw: BlockKind.image.rawValue, properties: BlockProperties(assetID: UUID())),
            // Aus einer späteren Version: Art und Mark bleiben erhalten.
            BlockSnapshot(id: UUID(), kindRaw: "callout", text: "Neu", richText: try rich(.init(text: "Neu", marks: ["glow"]))),
        ]
    }

    /// Zweites Gerät: lädt den Stand des ersten.
    static func copy(_ document: PageDocument) throws -> PageDocument {
        try PageDocument(bytes: document.save())
    }

    /// Tauscht die Änderungen beider Geräte aus, wie über den Ordner.
    static func exchange(_ a: PageDocument, _ b: PageDocument) throws {
        let fromA = try a.changes(since: nil), fromB = try b.changes(since: nil)
        try a.apply(changes: fromB)
        try b.apply(changes: fromA)
    }

    static func decoded(_ block: BlockSnapshot) -> RichText? { block.richText.flatMap(RichText.decode) }

    @Test func roundTripKeepsEveryField() throws {
        let blocks = try Self.sample()
        let document = PageDocument()
        #expect(try document.update(to: blocks))
        let loaded = try PageDocument(bytes: document.save()).blocks()
        #expect(loaded.map(\.id) == blocks.map(\.id))
        #expect(loaded.map(\.kindRaw) == blocks.map(\.kindRaw))
        #expect(loaded.map(\.text) == blocks.map(\.text))
        #expect(loaded.map(\.properties) == blocks.map(\.properties))
        #expect(loaded.map(Self.decoded) == blocks.map(Self.decoded))
    }

    @Test func unchangedBlocksMakeNoChange() throws {
        let blocks = try Self.sample()
        let document = PageDocument()
        try document.update(to: blocks)
        let version = document.version
        #expect(try document.update(to: blocks) == false)
        #expect(document.version == version)
    }

    @Test func removingFormattingClearsMarks() throws {
        var blocks = try Self.sample()
        let document = PageDocument()
        try document.update(to: blocks)
        blocks[1].richText = nil
        #expect(try document.update(to: blocks))
        #expect(try document.blocks()[1].richText == nil)
        blocks[1].richText = try Self.rich(.init(text: "Milch 🥛 und Brot", marks: ["code"]))
        try document.update(to: blocks)
        #expect(try Self.decoded(document.blocks()[1]) == RichText(runs: [.init(text: "Milch 🥛 und Brot", marks: ["code"])]))
    }

    @Test func runsThatDoNotMatchTheTextAreIgnored() throws {
        let block = BlockSnapshot(id: UUID(), text: "Neu", richText: try Self.rich(.init(text: "Alt", marks: ["bold"])))
        let document = PageDocument()
        try document.update(to: [block])
        #expect(try document.blocks()[0].richText == nil)
    }

    @Test func concurrentTypingInTheSameBlockIsMerged() throws {
        let id = UUID()
        let a = PageDocument()
        try a.update(to: [BlockSnapshot(id: id, text: "Hallo Welt")])
        let b = try Self.copy(a)
        try a.update(to: [BlockSnapshot(id: id, text: "Hallo schöne Welt")])
        try b.update(to: [BlockSnapshot(id: id, text: "Hallo Welt 🌍!")])
        try Self.exchange(a, b)
        #expect(try a.blocks() == b.blocks())
        #expect(try a.blocks()[0].text == "Hallo schöne Welt 🌍!")
    }

    @Test func movingABlockKeepsConcurrentTyping() throws {
        let first = BlockSnapshot(id: UUID(), text: "Eins"), second = BlockSnapshot(id: UUID(), text: "Zwei")
        let a = PageDocument()
        try a.update(to: [first, second])
        let b = try Self.copy(a)
        try a.update(to: [second, first])
        var typed = first
        typed.text = "Eins plus"
        try b.update(to: [typed, second])
        try Self.exchange(a, b)
        #expect(try a.blocks().map(\.text) == ["Zwei", "Eins plus"])
        #expect(try b.blocks() == a.blocks())
    }

    @Test func moveKeepsOtherOrderKeys() throws {
        let blocks = (0..<5).map { BlockSnapshot(id: UUID(), text: "\($0)") }
        let document = PageDocument()
        try document.update(to: blocks)
        let before = try orderKeys(document)
        try document.update(to: [blocks[0], blocks[2], blocks[3], blocks[1], blocks[4]])
        let after = try orderKeys(document)
        let changed = blocks.filter { before[$0.id] != after[$0.id] }.map(\.id)
        #expect(changed.count == 1)
        #expect(try document.blocks().map(\.text) == ["0", "2", "3", "1", "4"])
    }

    func orderKeys(_ document: PageDocument) throws -> [UUID: String] {
        var result: [UUID: String] = [:]
        for (id, key) in document.itemKeys() {
            let map = try #require(try document.map(key))
            if case .Scalar(.String(let order))? = try document.fields(of: map)["order"] { result[id] = order }
        }
        return result
    }

    @Test func twoValuesForTheSameFieldAreBothKept() throws {
        let id = UUID()
        let a = PageDocument()
        try a.update(to: [BlockSnapshot(id: id, text: "Titel")])
        let b = try Self.copy(a)
        try a.update(to: [BlockSnapshot(id: id, kindRaw: BlockKind.heading1.rawValue, text: "Titel")])
        try b.update(to: [BlockSnapshot(id: id, kindRaw: BlockKind.quote.rawValue, text: "Titel")])
        try Self.exchange(a, b)
        let conflicts = try a.conflicts()
        #expect(conflicts.map(\.objectID) == [id] && conflicts.map(\.field) == ["kind"])
        #expect(conflicts.map(\.values) == [["heading1", "quote"]])
        #expect(try b.conflicts() == conflicts)
        // Den vorne gezeigten Wert zurückzuschreiben (wie jeder Abgleich mit dem Stand
        // des Stores) löst nichts auf; erst ein anderer Wert ist eine Änderung.
        let shown = try a.blocks()[0].kindRaw
        let other = shown == "heading1" ? "quote" : "heading1"
        #expect(try !a.update(to: [BlockSnapshot(id: id, kindRaw: shown, text: "Titel")]))
        #expect(try a.conflicts() == conflicts)
        #expect(try a.update(to: [BlockSnapshot(id: id, kindRaw: other, text: "Titel")]))
        #expect(try a.conflicts().isEmpty)
        #expect(try a.blocks()[0].kindRaw == other)
    }

    // MARK: Wahl bei Konflikten (11.6)

    @Test func everyVersionNamesTheDeviceThatWroteIt() throws {
        let id = UUID(), deviceA = UUID(), deviceB = UUID()
        let a = PageDocument()
        a.write(as: deviceA)
        try a.update(to: [BlockSnapshot(id: id, text: "Titel")])
        let b = try Self.copy(a)
        b.write(as: deviceB)
        try a.update(to: [BlockSnapshot(id: id, kindRaw: BlockKind.heading1.rawValue, text: "Titel")])
        try b.update(to: [BlockSnapshot(id: id, kindRaw: BlockKind.quote.rawValue, text: "Titel")])
        try Self.exchange(a, b)
        let versions = try #require(try a.conflicts().first).versions
        #expect(versions == [ConflictVersion(value: "heading1", device: deviceA), ConflictVersion(value: "quote", device: deviceB)])
        #expect(try b.conflicts().first?.versions == versions)
        // Ohne `write(as:)` (vor 11.6) nennt die Änderung kein Gerät.
        #expect(SyncDocument.device(of: ActorId()) == nil)
        #expect(SyncDocument.device(of: SyncDocument.actor(device: deviceA)) == deviceA)
    }

    @Test func choosingTheShownValueStillResolvesTheConflict() throws {
        let id = UUID()
        let a = PageDocument()
        try a.update(to: [BlockSnapshot(id: id, text: "Titel")])
        let b = try Self.copy(a)
        try a.update(to: [BlockSnapshot(id: id, kindRaw: BlockKind.heading1.rawValue, text: "Titel")])
        try b.update(to: [BlockSnapshot(id: id, kindRaw: BlockKind.quote.rawValue, text: "Titel")])
        try Self.exchange(a, b)
        let shown = try a.blocks()[0].kindRaw
        #expect(try a.resolve(id, field: "kind", choosing: shown))
        #expect(try a.conflicts().isEmpty)
        #expect(try a.blocks()[0].kindRaw == shown)
        // Das andere Gerät übernimmt die Wahl.
        try b.apply(changes: a.changes(since: nil))
        #expect(try b.conflicts().isEmpty)
        #expect(try b.blocks()[0].kindRaw == shown)
    }

    @Test func choosingWithoutConflictOrWithAnUnknownValueChangesNothing() throws {
        let id = UUID()
        let a = PageDocument()
        try a.update(to: [BlockSnapshot(id: id, text: "Titel")])
        let version = a.version
        #expect(try !a.resolve(id, field: "kind", choosing: BlockKind.paragraph.rawValue))
        #expect(try !a.resolve(id, field: nil, choosing: "Map 1@ab"))
        #expect(try !a.resolve(UUID(), field: "kind", choosing: "quote"))
        #expect(a.version == version)
        let b = try Self.copy(a)
        try a.update(to: [BlockSnapshot(id: id, kindRaw: BlockKind.heading1.rawValue, text: "Titel")])
        try b.update(to: [BlockSnapshot(id: id, kindRaw: BlockKind.quote.rawValue, text: "Titel")])
        try Self.exchange(a, b)
        #expect(try !a.resolve(id, field: "kind", choosing: "code"))
        #expect(try a.conflicts().count == 1)
    }

    @Test func doubledBlockKeepsTheChosenVersion() throws {
        let id = UUID()
        let a = PageDocument(), b = PageDocument()
        try a.update(to: [BlockSnapshot(id: id, text: "Fassung A")])
        try b.update(to: [BlockSnapshot(id: id, kindRaw: BlockKind.todo.rawValue, text: "Fassung B")])
        try Self.exchange(a, b)
        let conflict = try #require(try a.conflicts().first { $0.field == nil })
        #expect(Set(conflict.versions.compactMap(\.summary)) == ["Fassung A", "Fassung B"])
        let chosen = try #require(conflict.versions.first { $0.summary == "Fassung B" })
        #expect(try a.resolve(id, field: nil, choosing: chosen.value))
        #expect(try a.conflicts().isEmpty)
        #expect(try a.blocks().map(\.text) == ["Fassung B"])
        #expect(try a.blocks().map(\.kindRaw) == [BlockKind.todo.rawValue])
        try b.apply(changes: a.changes(since: nil))
        #expect(try b.conflicts().isEmpty)
        #expect(try b.blocks().map(\.text) == ["Fassung B"])
    }

    @Test func removedMarksAreNotReported() throws {
        // `TextMarks` verlässt sich darauf, dass Automerge entfernte Marks nicht meldet.
        var blocks = try Self.sample()
        let document = PageDocument()
        try document.update(to: blocks)
        blocks[1].richText = nil
        try document.update(to: blocks)
        let key = blocks[1].id.uuidString
        let map = try #require(try document.map(key))
        guard case .Object(let text, .Text)? = try document.fields(of: map)["text"] else {
            Issue.record("Block ohne Text")
            return
        }
        #expect(try document.document.marks(obj: text).isEmpty)
    }

    @Test func deletingABlockOnOneDeviceRemovesItAfterMerge() throws {
        // Automerge entfernt den Block trotz gleichzeitiger Bearbeitung; wiederherstellen
        // muss die Sync-Schicht (ADR-026, Phase 11.3). Dieser Test hält das Verhalten fest.
        let keep = BlockSnapshot(id: UUID(), text: "bleibt"), gone = BlockSnapshot(id: UUID(), text: "weg")
        let a = PageDocument()
        try a.update(to: [keep, gone])
        let b = try Self.copy(a)
        try a.update(to: [keep])
        var edited = gone
        edited.text = "weg, aber bearbeitet"
        try b.update(to: [keep, edited])
        try Self.exchange(a, b)
        #expect(try a.blocks().map(\.id) == [keep.id])
    }

    @Test func independentlyCreatedDocumentsMergeWithoutConflict() throws {
        let a = PageDocument(), b = PageDocument()
        try a.update(to: [BlockSnapshot(id: UUID(), text: "von A")])
        try b.update(to: [BlockSnapshot(id: UUID(), text: "von B")])
        try Self.exchange(a, b)
        #expect(try Set(a.blocks().map(\.text)) == ["von A", "von B"])
        #expect(try a.blocks() == b.blocks())
        #expect(try a.conflicts().isEmpty)
    }

    @Test func everyLoadWritesAsANewActor() throws {
        // Zwei Sitzungen aus demselben Stand (z. B. nach einem eingespielten Backup)
        // dürfen keine Änderung mit derselben Akteurs-ID und Nummer erzeugen.
        let id = UUID()
        let original = PageDocument()
        try original.update(to: [BlockSnapshot(id: id, text: "Start")])
        let saved = original.save()
        let first = try PageDocument(bytes: saved), second = try PageDocument(bytes: saved)
        try first.update(to: [BlockSnapshot(id: id, text: "Start eins")])
        try second.update(to: [BlockSnapshot(id: id, text: "zwei Start")])
        try Self.exchange(first, second)
        #expect(try first.blocks()[0].text == "zwei Start eins")
        #expect(try first.blocks() == second.blocks())
    }

    @Test func changesSinceAVersionContainOnlyNewWork() throws {
        let id = UUID()
        let a = PageDocument()
        try a.update(to: [BlockSnapshot(id: id, text: "eins")])
        let b = try Self.copy(a)
        let version = a.version
        try a.update(to: [BlockSnapshot(id: id, text: "eins zwei")])
        let delta = try a.changes(since: version)
        #expect(delta.count < a.save().count)
        try b.apply(changes: delta)
        #expect(try b.blocks()[0].text == "eins zwei")
        // Doppelt angewendet schadet nicht.
        try b.apply(changes: delta)
        #expect(try b.blocks()[0].text == "eins zwei")
    }

    @Test func unreadableDataThrows() throws {
        #expect(throws: SyncError.self) { try PageDocument(bytes: Data("kaputt".utf8)) }
        #expect(throws: SyncError.malformed("blocks")) { try PageDocument(bytes: TreeDocument().save()) }
        let newer = try PageDocument.withFormat(PageDocument.formatVersion + 1)
        #expect(throws: SyncError.newerFormat(PageDocument.formatVersion + 1)) { try PageDocument(bytes: newer) }
    }
}

extension PageDocument {
    /// Gespeichertes Dokument, wie es eine spätere Version mit `format` schreiben würde.
    static func withFormat(_ format: Int) throws -> Data {
        let document = PageDocument()
        try document.document.put(obj: .ROOT, key: "format", value: .Int(Int64(format)))
        document.document.commitWith()
        return document.save()
    }
}

@Suite("Automerge-Daten prüfen")
struct ChunkCheckTests {
    static func changes() throws -> (PageDocument, Data) {
        let document = PageDocument()
        try document.update(to: [BlockSnapshot(id: UUID(), text: "Hallo")])
        return (document, try document.changes(since: nil))
    }

    @Test func validChangesSnapshotsAndSeveralChunksPass() throws {
        let (document, first) = try Self.changes()
        try ChunkCheck.validate(first)
        try ChunkCheck.validate(document.save())
        let version = document.version
        try document.update(to: [BlockSnapshot(id: UUID(), text: "Welt")])
        try ChunkCheck.validate(first + document.changes(since: version))
    }

    /// Automerge selbst nimmt all das ohne Fehler an; übernommen werden darf es nicht.
    @Test func emptyForeignTruncatedAndAlteredDataAreUnreadable() throws {
        let (_, valid) = try Self.changes()
        var altered = valid
        altered[altered.count - 1] ^= 0xFF
        for (name, data) in [
            ("leer", Data()), ("fremd", Data("kein Automerge".utf8)), ("abgeschnitten", valid.prefix(valid.count - 5)),
            ("nur Kopf", valid.prefix(6)), ("verändert", altered), ("Rest dahinter", valid + Data([0x85])),
        ] {
            #expect(throws: SyncError.self, "\(name)") { try PageDocument().apply(changes: data) }
            #expect(throws: SyncError.self, "\(name)") { try PageDocument(bytes: data) }
        }
    }
}
