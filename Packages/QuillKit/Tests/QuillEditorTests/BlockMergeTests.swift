import Foundation
@testable import QuillEditorCore
import QuillModel
import QuillTestFixtures
import Testing

/// Dreiwege-Abgleich je Block (`BlockMerge`): Was nur eine Seite geändert hat, gilt;
/// Änderungen beider am selben Block werden zusammengeführt oder bleiben beide.
@Suite("BlockMerge: Editor und Store zusammenführen")
struct BlockMergeTests {
    let a = UUID(), b = UUID(), c = UUID()

    @Test func onlyOneSideChanged() {
        let base = [EditorBlock(id: a, text: "eins"), EditorBlock(id: b, text: "zwei")]
        var local = base, remote = base
        local[0].text = "eins lokal"
        remote[1].text = "zwei aus dem Store"
        #expect(BlockMerge.merge(base: base, local: local, remote: remote).map(\.text) == ["eins lokal", "zwei aus dem Store"])
        #expect(BlockMerge.merge(base: base, local: base, remote: remote) == remote)
        #expect(BlockMerge.merge(base: base, local: local, remote: base) == local)
    }

    @Test func typingAtBothEndsOfTheSameBlockKeepsBoth() {
        let base = [EditorBlock(id: a, text: "Mitte")]
        let local = [EditorBlock(id: a, text: "Mitte BBB")]
        let remote = [EditorBlock(id: a, text: "AAA Mitte")]
        let merged = BlockMerge.merge(base: base, local: local, remote: remote)
        #expect(merged.map(\.text) == ["AAA Mitte BBB"])
        #expect(merged.map(\.id) == [a])
        #expect(!merged[0].isRestored)
    }

    @Test func insertingAtTheSamePlacePutsTheLocalTextFirst() {
        let merged = BlockMerge.merge(
            base: [EditorBlock(id: a, text: "x")],
            local: [EditorBlock(id: a, text: "xA")],
            remote: [EditorBlock(id: a, text: "xB")]
        )
        #expect(merged.map(\.text) == ["xAB"])
    }

    @Test func overlappingEditsKeepBothVersions() throws {
        let merged = BlockMerge.merge(
            base: [EditorBlock(id: a, text: "Der Hund bellt")],
            local: [EditorBlock(id: a, text: "Der Kater bellt")],
            remote: [EditorBlock(id: a, text: "Der Vogel bellt")]
        )
        #expect(merged.map(\.text) == ["Der Kater bellt", "Der Vogel bellt"])
        #expect(merged[0].id == a && !merged[0].isRestored)
        #expect(merged[1].id != a && merged[1].isRestored)
    }

    @Test func formattingAndTextFromBothSides() {
        let base = [EditorBlock(id: a, text: "fett und mehr")]
        // Im Store wurde „fett“ fett, im Editor hinten weitergetippt.
        let remote = [EditorBlock(id: a, text: "fett und mehr", spans: [InlineSpan(0..<4, marks: [.bold])])]
        let local = [EditorBlock(id: a, text: "fett und mehr Text")]
        let merged = BlockMerge.merge(base: base, local: local, remote: remote)
        #expect(merged.map(\.text) == ["fett und mehr Text"])
        #expect(merged[0].spans == [InlineSpan(0..<4, marks: [.bold])])

        // Vorne eingefügt verschiebt die Formatierung dahinter.
        let shifted = BlockMerge.merge(
            base: remote, local: [EditorBlock(id: a, text: "Ganz fett und mehr", spans: [InlineSpan(5..<9, marks: [.bold])])],
            remote: [EditorBlock(id: a, text: "fett und mehr!", spans: [InlineSpan(0..<4, marks: [.bold])])]
        )
        #expect(shifted.map(\.text) == ["Ganz fett und mehr!"])
        #expect(shifted[0].spans == [InlineSpan(5..<9, marks: [.bold])])
    }

    @Test func kindFieldsAndTextChangedOnDifferentSides() {
        let base = [EditorBlock(id: a, text: "Punkt")]
        let remote = [EditorBlock(id: a, kind: .todo, text: "Punkt", isChecked: true)]
        let local = [EditorBlock(id: a, text: "Punkt eins", indent: 1)]
        let merged = BlockMerge.merge(base: base, local: local, remote: remote)
        #expect(merged.count == 1)
        #expect(merged[0].kind == .todo && merged[0].isChecked && merged[0].indent == 1)
        #expect(merged[0].text == "Punkt eins")
    }

    @Test func sameFieldChangedDifferentlyKeepsBothVersions() {
        let merged = BlockMerge.merge(
            base: [EditorBlock(id: a, text: "Titel")],
            local: [EditorBlock(id: a, kind: .heading1, text: "Titel")],
            remote: [EditorBlock(id: a, kind: .quote, text: "Titel")]
        )
        #expect(merged.map(\.kind) == [.heading1, .quote])
        #expect(merged[1].isRestored)
    }

    @Test func deletedOnOneSideEditedOnTheOtherStays() {
        let base = [EditorBlock(id: a, text: "bleibt"), EditorBlock(id: b, text: "umstritten"), EditorBlock(id: c, text: "weg")]
        // Im Editor gelöscht: b und c; im Store b bearbeitet, c unverändert.
        let local = [base[0]]
        var remote = base
        remote[1].text = "umstritten, bearbeitet"
        let merged = BlockMerge.merge(base: base, local: local, remote: remote)
        #expect(merged.map(\.text) == ["bleibt", "umstritten, bearbeitet"])
        #expect(merged.map(\.isRestored) == [false, true])

        // Im Store gelöscht, im Editor bearbeitet.
        var edited = base
        edited[2].text = "doch nicht weg"
        let other = BlockMerge.merge(base: base, local: edited, remote: Array(base[0...1]))
        #expect(other.map(\.text) == ["bleibt", "umstritten", "doch nicht weg"])
        #expect(other.map(\.isRestored) == [false, false, true])
    }

    @Test func newBlocksFromBothSidesFollowTheirPredecessors() {
        let base = [EditorBlock(id: a, text: "a"), EditorBlock(id: b, text: "b")]
        let mine = EditorBlock(text: "nach a, lokal")
        let theirs = EditorBlock(text: "nach b, Store")
        let merged = BlockMerge.merge(base: base, local: [base[0], mine, base[1]], remote: base + [theirs])
        #expect(merged.map(\.text) == ["a", "nach a, lokal", "b", "nach b, Store"])
    }

    @Test func movedInTheStoreKeepsTheNewOrder() {
        let base = [EditorBlock(id: a, text: "a"), EditorBlock(id: b, text: "b"), EditorBlock(id: c, text: "c")]
        var local = base
        local[1].text = "b lokal"
        let remote = [base[2], base[0], base[1]]
        #expect(BlockMerge.merge(base: base, local: local, remote: remote).map(\.text) == ["c", "a", "b lokal"])
        // Hat der Editor selbst umgestellt, gilt seine Reihenfolge.
        let moved = [base[1], base[0], base[2]]
        #expect(BlockMerge.merge(base: base, local: moved, remote: remote).map(\.text) == ["b", "a", "c"])
    }

    @Test func emojiAndFlagsStayIntact() {
        let merged = BlockMerge.merge(
            base: [EditorBlock(id: a, text: "🇩🇪 und 🥛")],
            local: [EditorBlock(id: a, text: "🇩🇪 und 🍞")],
            remote: [EditorBlock(id: a, text: "🇫🇷 und 🥛")]
        )
        #expect(merged.map(\.text) == ["🇫🇷 und 🍞"])
    }

    @Test func everyBlockFieldIsMerged() {
        // Ein neues Feld in `BlockProperties` braucht eine Zeile in `mergeProperties`
        // (ADR-014); sonst bliebe hier der lokale Wert stehen.
        let full = SampleDocuments.fullProperties, plain = BlockProperties()
        #expect(BlockMerge.mergeProperties(plain, plain, full) == full)
        #expect(BlockMerge.mergeProperties(full, full, plain) == plain)
    }

    @Test func caretFollowsTheChange() {
        // Vorne eingefügt: der Cursor am Ende bleibt am Ende.
        #expect(BlockMerge.mappedOffset(5, from: "Mitte", to: "AAA Mitte") == 9)
        // Hinten angefügt: der Cursor davor bleibt.
        #expect(BlockMerge.mappedOffset(2, from: "Mitte", to: "Mitte BBB") == 2)
        // In der geänderten Stelle: ans Ende der Änderung.
        #expect(BlockMerge.mappedOffset(5, from: "Der Hund bellt", to: "Der Vogel bellt") == 9)
        #expect(BlockMerge.mappedOffset(3, from: "abc", to: "") == 0)
    }
}
