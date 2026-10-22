import Foundation
@testable import QuillEditorCore
import QuillModel
import Testing

/// Absätze aus einem früheren Stand zurückholen (Zeitreise, 12.3, ADR-031).
@Suite("Zeitreise: Absätze zurückholen")
struct EditorRestoreTests {
    private let a = EditorBlock(text: "A", properties: BlockProperties())
    private let b = EditorBlock(text: "B", properties: BlockProperties())
    private let c = EditorBlock(text: "C", properties: BlockProperties())

    @Test func existingBlockGetsItsEarlierContentInPlace() {
        var changedB = b
        changedB.text = "B neu"
        changedB.kind = .heading1
        var document = EditorDocument(blocks: [c, changedB, a])
        let restored = document.restore([b.id], from: [a, b, c])
        #expect(restored == [b.id])
        #expect(document.blocks == [c, b, a])
    }

    @Test func deletedBlockComesBackAfterItsNearestEarlierNeighbour() {
        // A, B, C damals; heute ohne B: B kommt hinter A.
        var document = EditorDocument(blocks: [a, c])
        document.restore([b.id], from: [a, b, c])
        #expect(document.blocks.map(\.text) == ["A", "B", "C"])

        // Ohne A und B heute: Ohne Vorgänger an den Anfang, B danach in alter Reihenfolge.
        var withoutBoth = EditorDocument(blocks: [c])
        let restored = withoutBoth.restore([a.id, b.id], from: [a, b, c])
        #expect(restored == [a.id, b.id])
        #expect(withoutBoth.blocks.map(\.text) == ["A", "B", "C"])
    }

    @Test func emptyPageIsReplacedNotExtended() {
        var document = EditorDocument()
        document.restore([a.id, b.id], from: [a, b, c])
        #expect(document.blocks.map(\.text) == ["A", "B"])

        // Ein Absatz mit Text ist keine leere Seite.
        var typed = EditorDocument(blocks: [EditorBlock(text: "Neu", properties: BlockProperties())])
        typed.restore([a.id], from: [a, b])
        #expect(typed.blocks.map(\.text) == ["A", "Neu"])
    }

    @Test func blocksNotChosenStayUntouched() {
        var newerC = c
        newerC.text = "C neu"
        var document = EditorDocument(blocks: [newerC])
        document.restore([], from: [a, b, c])
        #expect(document.blocks == [newerC])
    }
}
