import Foundation
@testable import QuillFeatures
import QuillModel
import Testing

/// Seiten in Spotlight (15.2, ADR-033), mit einem Index im Speicher statt dem des Macs.
@Suite("Spotlight: Index")
@MainActor
struct SpotlightIndexingTests {
    let store: PageStore
    let index = MemorySpotlightIndex()

    init() throws {
        store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
    }

    func indexing(defaults: UserDefaults? = nil) -> SpotlightIndexing {
        SpotlightIndexing(store: store, index: index, defaults: defaults, delay: .milliseconds(10))
    }

    @discardableResult
    func page(_ title: String, _ texts: [String]) async throws -> UUID {
        let id = try await store.createPage(title: title)
        let blocks = texts.map { BlockSnapshot(id: UUID(), text: $0) }
        try await store.applyEdits(id, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        return id
    }

    func entries() async -> [String: String] {
        Dictionary(uniqueKeysWithValues: await index.entries.values.map { ($0.title, $0.text) })
    }

    /// Wartet, bis der Index die Erwartung erfüllt (Speichern meldet sich über eine Notification).
    func waitFor(_ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) async throws {
        for _ in 0..<200 {
            if await entries() == expected { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await entries() == expected, sourceLocation: sourceLocation)
    }

    @Test func offByDefaultWritesNothing() async throws {
        try await page("Einkauf", ["Milch"])
        let spotlight = indexing()
        spotlight.start()
        await spotlight.settle()
        #expect(!spotlight.isEnabled)
        #expect(await index.entries.isEmpty)
        #expect(await index.rebuilds == 0)
    }

    @Test func enablingIndexesTitleAndTextWithoutTrash() async throws {
        try await page("Einkauf", ["Milch", "Brot"])
        try await page("", ["Ohne Titel"])
        let trashed = try await page("Alt", ["weg"])
        try await store.trash(trashed)

        let spotlight = indexing()
        spotlight.setEnabled(true)
        await spotlight.settle()
        #expect(await entries() == ["Einkauf": "Milch\nBrot", "": "Ohne Titel"])
        #expect(await index.rebuilds == 1)
    }

    @Test func savedChangesFollowAndTrashedPagesLeave() async throws {
        let shopping = try await page("Einkauf", ["Milch"])
        let old = try await page("Alt", ["weg"])
        let spotlight = indexing()
        spotlight.setEnabled(true)
        await spotlight.settle()

        try await store.rename(shopping, to: "Wocheneinkauf")
        try await store.trash(old)
        try await page("Neu", ["frisch"])
        try await waitFor(["Wocheneinkauf": "Milch", "Neu": "frisch"])
        #expect(await index.rebuilds == 1, "Änderungen nachgetragen, nicht neu aufgebaut")
    }

    @Test func turningOffRemovesEverythingAndStopsFollowing() async throws {
        try await page("Einkauf", ["Milch"])
        let suite = "io.github.vogelwild07.quill.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let spotlight = indexing(defaults: defaults)
        spotlight.setEnabled(true)
        await spotlight.settle()
        #expect(indexing(defaults: defaults).isEnabled, "Wahl pro Mac gespeichert")

        spotlight.setEnabled(false)
        await spotlight.settle()
        #expect(await index.entries.isEmpty)
        try await page("Später", ["nicht im Index"])
        try await Task.sleep(for: .milliseconds(100))
        await spotlight.settle()
        #expect(await index.entries.isEmpty)
        #expect(!indexing(defaults: defaults).isEnabled)
    }

    @Test func longPagesWithTheirBeginning() async throws {
        try await page("Lang", [String(repeating: "a", count: SpotlightIndexing.textLimit), "Ende"])
        let spotlight = indexing()
        spotlight.setEnabled(true)
        await spotlight.settle()
        let text = try #require(await index.entries.values.first?.text)
        #expect(text.count == SpotlightIndexing.textLimit)
        #expect(!text.contains("Ende"))
    }

    @Test func testStoresNeverWriteToTheIndexOfTheMac() throws {
        let persistence = QuillPersistence(container: try QuillStore.makeInMemoryContainer(), backup: nil)
        #expect(persistence.isTestStore)
        #expect(persistence.spotlight.index is MemorySpotlightIndex)
    }
}
