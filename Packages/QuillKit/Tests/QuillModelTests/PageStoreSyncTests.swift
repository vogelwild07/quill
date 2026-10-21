import Foundation
import SwiftData
import Testing
@testable import QuillModel

/// Schreibwege der Sync-Schicht (ADR-029): nur übernehmen, wenn der Store noch dem
/// erwarteten Stand entspricht; Seiten nie löschen; Kreise im Seitenbaum auflösen.
@Suite("PageStore: Schreibwege für den Sync")
struct PageStoreSyncTests {
    let container: ModelContainer
    let store: PageStore

    init() throws {
        container = try QuillStore.makeInMemoryContainer()
        store = PageStore(modelContainer: container)
    }

    func snapshot(_ id: UUID) async throws -> PageSnapshot {
        try #require(try await store.pageSnapshots().first { $0.id == id })
    }

    @Test func syncStateAndDeviceID() async throws {
        #expect(try await store.syncState() == SyncStoreState(deviceID: nil, tree: nil, cursors: nil))
        let device = UUID()
        try await store.setSyncDeviceID(device)
        #expect(try await store.syncState().deviceID == device)
        try await store.saveSyncCursors(Data("c".utf8))
        #expect(try await store.syncState().cursors == Data("c".utf8))
    }

    @Test func restoredMarkIsSetAndClearedAsAChange() async throws {
        let page = try await store.createPage(title: "Notiz")
        let dates = try await store.pageUpdateDates()
        try await store.setRestored(page, true)
        #expect(try await snapshot(page).isRestored)
        let marked = try await store.pageUpdateDates()
        // Der Abgleich sieht die Änderung (ADR-029: fällig ist, was neuer ist).
        #expect(try #require(marked[page]) > #require(dates[page]))
        try await store.setRestored(page, true)
        #expect(try await store.pageUpdateDates() == marked)
        try await store.setRestored(page, false)
        #expect(try await !snapshot(page).isRestored)
    }

    @Test func treeChangesCreateUpdateAndTrashButNeverDelete() async throws {
        let existing = try await store.createPage(title: "Alt")
        let before = try await snapshot(existing)
        var renamed = before
        renamed.title = "Neu"
        renamed.trashedAt = Date(timeIntervalSinceReferenceDate: 1000)
        renamed.isRestored = true
        let created = PageSnapshot(id: UUID(), title: "Von anderem Gerät", parentID: existing, sortKey: "a0")
        let applied = try await store.applySyncTree(
            [PageSnapshotChange(expected: before, new: renamed), PageSnapshotChange(expected: nil, new: created)],
            tree: Data("t".utf8), cursors: Data("c".utf8)
        )
        #expect(applied)
        #expect(try await snapshot(existing) == renamed)
        #expect(try await snapshot(created.id) == created)
        let state = try await store.syncState()
        #expect(state.tree == Data("t".utf8) && state.cursors == Data("c".utf8))
    }

    @Test func treeChangeIsSkippedWhenTheUserChangedThePageMeanwhile() async throws {
        let page = try await store.createPage(title: "Alt")
        let expected = try await snapshot(page)
        try await store.rename(page, to: "Vom Nutzer, während des Abgleichs")
        var incoming = expected
        incoming.title = "Vom anderen Gerät"
        let other = PageSnapshot(id: UUID(), title: "Neu")
        let applied = try await store.applySyncTree(
            [PageSnapshotChange(expected: expected, new: incoming), PageSnapshotChange(expected: nil, new: other)],
            tree: Data("t".utf8), cursors: Data("c".utf8)
        )
        #expect(!applied)
        #expect(try await snapshot(page).title == "Vom Nutzer, während des Abgleichs")
        // Nichts davon geschrieben, auch nicht die neue Seite oder der Sync-Stand.
        #expect(try await store.pageSnapshots().count == 1)
        #expect(try await store.syncState().tree == nil)
    }

    @Test func missingParentPutsThePageOnTop() async throws {
        let page = PageSnapshot(id: UUID(), title: "Waise", parentID: UUID())
        #expect(try await store.applySyncTree([PageSnapshotChange(expected: nil, new: page)], tree: Data(), cursors: Data()))
        #expect(try await snapshot(page.id).parentID == nil)
    }

    @Test func crossedMovesFromTwoDevicesAreNoCycle() async throws {
        let first = try await store.createPage(title: "Eins")
        let second = try await store.createPage(title: "Zwei")
        let a = try await snapshot(first), b = try await snapshot(second)
        var aUnderB = a, bUnderA = b
        aUnderB.parentID = second
        bUnderA.parentID = first
        #expect(try await store.applySyncTree(
            [PageSnapshotChange(expected: a, new: aUnderB), PageSnapshotChange(expected: b, new: bUnderA)],
            tree: Data(), cursors: Data()
        ))
        let smaller = first.uuidString < second.uuidString ? first : second
        let larger = smaller == first ? second : first
        #expect(try await snapshot(smaller).parentID == nil)
        #expect(try await snapshot(larger).parentID == smaller)
    }

    @Test func pageEditsApplyOnlyFromTheExpectedBlocks() async throws {
        let page = try await store.createPage(title: "Seite")
        let block = BlockSnapshot(id: UUID(), text: "Alt")
        try await store.applyEdits(page, BlockEdits(upserts: [block], order: [block.id]))
        let expected = try await store.blocks(of: page)
        var incoming = block
        incoming.text = "Vom anderen Gerät"
        let added = BlockSnapshot(id: UUID(), text: "Dazu")

        // Der Nutzer tippt während des Abgleichs: nichts übernommen.
        var typed = block
        typed.text = "Vom Nutzer"
        try await store.applyEdits(page, BlockEdits(upserts: [typed]))
        let skipped = try await store.applySyncPage(
            page, expected: expected, edits: BlockEdits(upserts: [incoming, added], order: [block.id, added.id]),
            document: Data("d".utf8), cursors: Data("c".utf8)
        )
        #expect(skipped == nil)
        #expect(try await store.blocks(of: page).map(\.text) == ["Vom Nutzer"])
        #expect(try await store.syncPage(page)?.document == nil)

        // Vom erwarteten Stand aus: übernommen, mit Dokument und gelesenen Dateien.
        let current = try await store.blocks(of: page)
        let updated = try await store.applySyncPage(
            page, expected: current, edits: BlockEdits(upserts: [incoming, added], order: [block.id, added.id]),
            document: Data("d".utf8), cursors: Data("c".utf8)
        )
        #expect(updated != nil)
        #expect(try await store.blocks(of: page).map(\.text) == ["Vom anderen Gerät", "Dazu"])
        #expect(try await store.syncPage(page)?.document == Data("d".utf8))
        #expect(try await store.syncState().cursors == Data("c".utf8))
        #expect(try await store.pageUpdateDates()[page] == updated)
    }

    @Test func resetForgetsOnlyTheReadFiles() async throws {
        let page = try await store.createPage(title: "Bleibt")
        let block = BlockSnapshot(id: UUID(), text: "Text")
        try await store.applyEdits(page, BlockEdits(upserts: [block], order: [block.id]))
        let current = try await store.blocks(of: page)
        _ = try await store.applySyncPage(page, expected: current, edits: BlockEdits(), document: Data("d".utf8), cursors: Data("c".utf8))
        let device = UUID()
        try await store.setSyncDeviceID(device)
        _ = try await store.applySyncTree([], tree: Data("t".utf8), cursors: Data("c".utf8))
        let before = try await snapshot(page)

        try await store.resetSyncCursors()
        // Dokumente samt Geschichte bleiben; nur die Nummern des bisherigen Ordners gehen.
        #expect(try await store.syncState() == SyncStoreState(deviceID: device, tree: Data("t".utf8), cursors: nil))
        #expect(try await store.syncPage(page)?.document == Data("d".utf8))
        #expect(try await snapshot(page) == before)
    }

    @Test func syncedImagesKeepTheirBytes() async throws {
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg=="))
        let id = UUID()
        #expect(try await !store.hasAsset(id))
        try await store.insertSyncedAsset(id: id, data: png, uti: "public.png")
        #expect(try await store.hasAsset(id))
        let stored = try #require(try await store.imageData(id))
        #expect(stored.data == png)
        #expect(ImageImport.pixelSize(of: png).map { [$0.width, $0.height] } == [2, 3])
        // Ein zweites Mal ändert nichts.
        try await store.insertSyncedAsset(id: id, data: Data("anders".utf8), uti: "public.png")
        #expect(try await store.imageData(id)?.data == png)
    }
}
