import Foundation
@testable import QuillEditor
@testable import QuillEditorCore
import QuillModel
import SwiftData
import Testing

/// Jedes Feld von `BlockProperties` muss jeden Weg überstehen: Store, Snapshot,
/// Editor, Textspeicher und Zwischenablage. Ein neues Feld braucht in `full` einen
/// Wert, der vom Standard abweicht, sonst schlägt `fixtureSetsEveryField` fehl.
@MainActor
@Suite("BlockProperties: Vollständigkeit", .serialized)
struct BlockPropertiesRoundTripTests {
    static let full = BlockProperties(indent: 2, isChecked: true, codeLanguage: "swift", assetID: UUID())

    @Test func fixtureSetsEveryField() throws {
        let defaults = Dictionary(uniqueKeysWithValues: Mirror(reflecting: BlockProperties()).children.map {
            ($0.label ?? "", String(describing: $0.value))
        })
        let fields = Mirror(reflecting: Self.full).children
        #expect(!fields.isEmpty)
        for field in fields {
            let label = try #require(field.label)
            #expect(String(describing: field.value) != defaults[label], "Feld \(label) hat in den Testdaten den Standardwert")
        }
    }

    @Test func everyFieldSurvivesEveryPath() async throws {
        let container = try QuillStore.makeInMemoryContainer()
        let store = PageStore(modelContainer: container)
        let pageID = try await store.createPage(title: "Test")
        func storedProperties() throws -> BlockProperties? {
            try ModelContext(container).fetch(FetchDescriptor<Block>()).first?.properties
        }
        // Das Asset muss existieren, sonst verknüpft der Store nichts.
        let context = ModelContext(container)
        let asset = Asset(data: Data([1, 2, 3]))
        asset.id = try #require(Self.full.assetID)
        context.insert(asset)
        try context.save()

        // Editor → Store (neuer Block)
        let original = EditorBlock(kind: .todo, text: "Aufgabe", properties: Self.full)
        try await store.applyEdits(pageID, BlockEdits(upserts: [original.snapshot], order: [original.id]))
        #expect(try storedProperties() == Self.full)

        // Store → Editor
        let loaded = try #require(try await store.blocks(of: pageID).first)
        let block = EditorBlock(snapshot: loaded)
        #expect(block.properties == Self.full)

        // Editor → Textspeicher → Editor
        let (parsed, _) = BlockRenderer.parse(BlockRenderer.render([block][...], ordinals: [:]))
        #expect(parsed.first?.properties == Self.full)

        // Zwischenablage
        let data = try #require(BlockClipboard.encode(parsed))
        let pasted = try #require(BlockClipboard.decode(data)?.first)
        #expect(pasted.properties == Self.full)

        // Editor → Store (bestehender Block): erst zurück auf Standard, dann wieder voll
        var edited = pasted
        edited.properties = BlockProperties()
        try await store.applyEdits(pageID, BlockEdits(upserts: [edited.snapshot]))
        #expect(try storedProperties() == BlockProperties())
        edited.properties = Self.full
        try await store.applyEdits(pageID, BlockEdits(upserts: [edited.snapshot]))
        #expect(try storedProperties() == Self.full)
    }

    @Test func normalizedKeepsOnlyFieldsThatFitTheKind() {
        #expect(Self.full.normalized(for: .todo) == BlockProperties(indent: 2, isChecked: true))
        #expect(Self.full.normalized(for: .code) == BlockProperties(codeLanguage: "swift"))
        #expect(Self.full.normalized(for: .bulleted) == BlockProperties(indent: 2))
        #expect(Self.full.normalized(for: .heading2) == BlockProperties())
        #expect(Self.full.normalized(for: .divider) == BlockProperties())
        #expect(Self.full.normalized(for: .image) == BlockProperties(assetID: Self.full.assetID))
        #expect(BlockProperties(indent: 99).normalized(for: .paragraph).indent == EditorDocument.maxIndent)
    }
}
