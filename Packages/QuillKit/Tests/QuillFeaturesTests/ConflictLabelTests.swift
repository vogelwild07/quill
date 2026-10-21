import Foundation
@testable import QuillFeatures
import QuillModel
import QuillSync
import Testing

/// Wahl bei Konflikten (11.6): Felder und Fassungen in Worten statt Rohwerten.
@Suite("Konflikte: Texte für Feld und Fassung")
struct ConflictLabelTests {
    static func conflict(_ field: String?, tree: Bool = false, _ versions: [ConflictVersion]) -> PageConflict {
        PageConflict(
            documentID: tree ? SyncReport.treeID : UUID(),
            conflict: FieldConflict(objectID: UUID(), field: field, versions: versions)
        )
    }

    static func texts(_ conflict: PageConflict, titles: [UUID: String] = [:]) -> [String] {
        conflict.conflict.versions.map { ConflictLabel.value($0, in: conflict, pageTitle: { titles[$0] }) }
    }

    @Test func blockFieldsInWords() {
        let kind = Self.conflict("kind", [ConflictVersion(value: "heading2"), ConflictVersion(value: "todo"), ConflictVersion(value: "kanban")])
        #expect(ConflictLabel.field(kind) == "Blockart")
        // Unbekannte Art einer späteren Version: der Rohwert.
        #expect(Self.texts(kind) == ["Überschrift 2", "To-do", "kanban"])
        #expect(Self.texts(Self.conflict("checked", [ConflictVersion(value: "false"), ConflictVersion(value: "true")])) == ["offen", "erledigt"])
        #expect(Self.texts(Self.conflict("indent", [ConflictVersion(value: "1")])) == ["Stufe 1"])
        #expect(Self.texts(Self.conflict("lang", [ConflictVersion(value: ""), ConflictVersion(value: "swift")])) == ["keine", "swift"])
    }

    @Test func pageFieldsInWords() {
        let parent = UUID()
        let place = Self.conflict("parent", tree: true, [ConflictVersion(value: parent.uuidString), ConflictVersion(value: "null")])
        #expect(ConflictLabel.field(place) == "Ort")
        #expect(Self.texts(place, titles: [parent: "Arbeit"]) == ["Arbeit", "Oberste Ebene"])
        #expect(Self.texts(Self.conflict("title", tree: true, [ConflictVersion(value: "")])) == ["Ohne Titel"])
    }

    @Test func doubledObjectsShowTheirContent() {
        let block = Self.conflict(nil, [ConflictVersion(value: "Map 1@a", summary: "Fassung A"), ConflictVersion(value: "Map 2@b", summary: " ")])
        #expect(ConflictLabel.field(block) == "Ganzer Block")
        #expect(Self.texts(block) == ["„Fassung A“", "Leerer Block"])
        let page = Self.conflict(nil, tree: true, [ConflictVersion(value: "Map 1@a", summary: "Notiz")])
        #expect(ConflictLabel.field(page) == "Ganze Seite")
        #expect(Self.texts(page) == ["Notiz"])
    }
}
