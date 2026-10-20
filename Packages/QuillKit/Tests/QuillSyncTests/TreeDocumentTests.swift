import Foundation
import QuillModel
import Testing
@testable import QuillSync

@Suite("Baum-Dokument: Seiten, Papierkorb, Grabstein")
struct TreeDocumentTests {
    static let created = Date(timeIntervalSince1970: 1_800_000_000)

    static func record(_ title: String, parent: UUID? = nil) -> PageRecord {
        PageRecord(id: UUID(), title: title, parentID: parent, sortKey: "a0", createdAt: created)
    }

    static func exchange(_ a: TreeDocument, _ b: TreeDocument) throws {
        let fromA = try a.changes(since: nil), fromB = try b.changes(since: nil)
        try a.apply(changes: fromB)
        try b.apply(changes: fromA)
    }

    @Test func roundTripKeepsEveryField() throws {
        let root = Self.record("Projekte")
        var child = PageRecord(
            id: UUID(), title: "Quill 🪶", icon: "🪶", parentID: root.id, sortKey: "a1", isFavorite: true,
            favoriteSortKey: "a0", trashedAt: Self.created.addingTimeInterval(60), kindRaw: "board", createdAt: Self.created,
            isRestored: true
        )
        let document = TreeDocument()
        #expect(try document.update([root, child]))
        let loaded = try TreeDocument(bytes: document.save()).records()
        #expect(Set(loaded.map(\.id)) == [root.id, child.id])
        #expect(loaded.first { $0.id == child.id } == child)
        #expect(loaded.first { $0.id == root.id } == root)
        // Felder entfernen
        child.icon = nil
        child.favoriteSortKey = nil
        child.trashedAt = nil
        child.isRestored = false
        try document.update([child])
        #expect(try document.records().first { $0.id == child.id } == child)
        #expect(try document.update([child]) == false)
    }

    /// Datumswerte kommen bit-gleich zurück, sonst sähe der Abgleich bei jedem Lauf
    /// eine Änderung. Diese Werte runden über Sekunden seit 1970 (geprüft).
    @Test func datesSurviveExactly() throws {
        let dates = [812_345_678.987_654_3, 808_080_808.080_808].map { Date(timeIntervalSinceReferenceDate: $0) }
        let document = TreeDocument()
        let records = dates.map { PageRecord(id: UUID(), trashedAt: $0, createdAt: $0) }
        try document.update(records)
        let loaded = try TreeDocument(bytes: document.save()).records()
        for record in records {
            let back = try #require(loaded.first { $0.id == record.id })
            #expect(back.trashedAt == record.trashedAt)
            #expect(back.createdAt == record.createdAt)
        }
    }

    @Test func deletedPagesStayAsTombstoneInTheTrash() throws {
        let page = Self.record("Weg")
        let document = TreeDocument()
        try document.update([page])
        let deleted = Self.created.addingTimeInterval(120)
        #expect(try document.markDeleted(page.id, at: deleted))
        let record = try #require(try document.records().first)
        #expect(record.deletedAt == deleted)
        #expect(record.trashedAt == deleted)
        // Ein späteres Update ohne Grabstein nimmt ihn nicht zurück.
        var restored = record
        restored.deletedAt = nil
        restored.trashedAt = nil
        try document.update([restored])
        #expect(try document.records().first?.deletedAt == deleted)
        #expect(try document.markDeleted(page.id) == false)
    }

    @Test func pagesMissingFromAnUpdateStay() throws {
        let a = Self.record("A"), b = Self.record("B")
        let document = TreeDocument()
        try document.update([a, b])
        try document.update([a])
        #expect(try document.records().count == 2)
    }

    @Test func concurrentTitlesAndMovesAreConflicts() throws {
        let parentA = Self.record("Arbeit"), parentB = Self.record("Privat"), page = Self.record("Notiz")
        let a = TreeDocument()
        try a.update([parentA, parentB, page])
        let b = try TreeDocument(bytes: a.save())
        var onA = page, onB = page
        onA.title = "Notiz A"
        onA.parentID = parentA.id
        onB.title = "Notiz B"
        onB.parentID = parentB.id
        try a.update([onA])
        try b.update([onB])
        try Self.exchange(a, b)
        let conflicts = try a.conflicts()
        #expect(conflicts.map(\.field) == ["parent", "title"])
        #expect(conflicts.allSatisfy { $0.objectID == page.id })
        #expect(conflicts.last?.values == ["Notiz A", "Notiz B"])
        #expect(try b.conflicts() == conflicts)
    }

    @Test func trashAgainstEditIsNoFieldConflict() throws {
        // Papierkorb gegen Bearbeiten entscheidet die Sync-Schicht (die Seite bleibt).
        let page = Self.record("Notiz")
        let a = TreeDocument()
        try a.update([page])
        let b = try TreeDocument(bytes: a.save())
        var trashed = page, renamed = page
        trashed.trashedAt = Self.created
        renamed.title = "Notiz, umbenannt"
        try a.update([trashed])
        try b.update([renamed])
        try Self.exchange(a, b)
        #expect(try a.conflicts().isEmpty)
        let merged = try #require(try a.records().first)
        #expect(merged.title == "Notiz, umbenannt")
        #expect(merged.trashedAt == Self.created)
    }

    @Test func independentlyCreatedTreesMergeWithoutConflict() throws {
        let a = TreeDocument(), b = TreeDocument()
        try a.update([Self.record("von A")])
        try b.update([Self.record("von B")])
        try Self.exchange(a, b)
        #expect(try Set(a.records().map(\.title)) == ["von A", "von B"])
        #expect(try a.conflicts().isEmpty)
    }
}
