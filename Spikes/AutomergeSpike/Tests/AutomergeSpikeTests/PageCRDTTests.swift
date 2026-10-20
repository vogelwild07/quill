import Automerge
import Foundation
import QuillEditor
import QuillModel
import Testing
@testable import AutomergeSpike

/// Verhalten, das ADR-026 von Automerge braucht. Keine Kriterien des Spikes, aber
/// Voraussetzung dafür, dass die Zahlen etwas bedeuten.
@Suite("Automerge-Spike: Abbildung und Zusammenführen")
struct PageCRDTTests {
    static let blocks: [EditorBlock] = [
        EditorBlock(kind: .heading1, text: "Einkauf 🙂"),
        // Überlappende Marks und ein Link hinter einem Zeichen außerhalb der BMP.
        EditorBlock(text: "🙂 fett und kursiv mit Link", spans: [
            InlineSpan(3..<12, marks: [.bold]),
            InlineSpan(8..<19, marks: [.italic]),
            InlineSpan(24..<28, marks: [], link: "https://example.com"),
        ]),
        EditorBlock(kind: .todo, text: "Käse", isChecked: true),
        EditorBlock(kind: .bulleted, text: "eingerückt", indent: 1),
        EditorBlock(kind: .code, text: "let a = 1\nlet b = 2", codeLanguage: "swift"),
        EditorBlock(kind: .divider),
        EditorBlock(kind: .image, properties: BlockProperties(assetID: UUID())),
        EditorBlock(kind: .quote, text: "Zitat"),
    ]

    @Test func blocksSurviveSaveAndLoad() throws {
        let page = try PageCRDT(blocks: Self.blocks)
        let loaded = try PageCRDT(bytes: page.document.save())
        #expect(try loaded.blocks() == Self.blocks)
    }

    @Test func concurrentTypingInTheSameBlockKeepsBoth() throws {
        let base = try PageCRDT(blocks: [EditorBlock(text: "Mitte")])
        let mac = try base.fork(), other = try base.fork()
        try mac.document.spliceText(obj: mac.textObject(at: 0), start: 0, delete: 0, value: "Anfang ")
        try other.document.spliceText(obj: other.textObject(at: 0), start: 5, delete: 0, value: " Ende")
        mac.document.commitWith()
        other.document.commitWith()
        try mac.merge(other)
        try other.merge(mac)
        #expect(try mac.blocks()[0].text == "Anfang Mitte Ende")
        #expect(try other.blocks() == mac.blocks())
    }

    /// Zwei Geräte ändern dasselbe Feld: Automerge wählt einen Gewinner, meldet aber
    /// beide Werte. Die Sync-Schicht kann den Konflikt also anzeigen (ADR-026).
    @Test func conflictingFieldValuesAreReported() throws {
        let base = try PageCRDT(blocks: [EditorBlock(text: "Titel?")])
        let mac = try base.fork(), other = try base.fork()
        try mac.document.put(obj: mac.map(at: 0), key: "kind", value: .String(BlockKind.heading1.rawValue))
        try other.document.put(obj: other.map(at: 0), key: "kind", value: .String(BlockKind.quote.rawValue))
        try mac.merge(other)
        let values = try mac.document.getAll(obj: mac.map(at: 0), key: "kind")
        #expect(values == [.Scalar(.String("heading1")), .Scalar(.String("quote"))])
    }

    /// Löschen gegen Bearbeiten: Automerge entfernt den Block. Die Bearbeitung bleibt
    /// in der Geschichte lesbar; wiederherstellen muss die Sync-Schicht selbst.
    @Test func deletedBlockKeepsConcurrentEditInHistory() throws {
        let base = try PageCRDT(blocks: [EditorBlock(text: "erster"), EditorBlock(text: "zweiter")])
        let mac = try base.fork(), other = try base.fork()
        try mac.document.delete(obj: mac.blocksID, index: 1)
        mac.document.commitWith()
        let text = try other.textObject(at: 1)
        try other.document.spliceText(obj: text, start: 7, delete: 0, value: " mit Nachtrag")
        other.document.commitWith()
        let otherHeads = other.document.heads()
        try mac.merge(other)
        #expect(try mac.blocks().map(\.text) == ["erster"])
        #expect(try mac.document.textAt(obj: text, heads: otherHeads) == "zweiter mit Nachtrag")
    }

    @Test func simulatedPageMatchesItsHistory() throws {
        var simulator = try PageHistorySimulator(words: 300, granularity: .perWord, seed: 7)
        let page = try simulator.run()
        let loaded = try PageCRDT(bytes: page.document.save())
        #expect(try loaded.blocks() == page.blocks())
        #expect(simulator.deletions > 0)
        #expect(page.document.getHistory().count > 300)
    }
}
