import Foundation
import QuillModel
import Synchronization
import Testing
@testable import QuillSync

/// Abgleich zweier Geräte über einen Ordner, mit allen Fällen aus ADR-026 und den
/// Vorgaben aus ADR-029. Nur Stores im Arbeitsspeicher und Wegwerf-Ordner.
@Suite("Abgleich: zwei Geräte, ein Ordner")
struct SyncEngineTests {
    // MARK: Grundlagen

    @Test func firstSyncWritesTheFolderFormatAndNothingTwice() async throws {
        let folder = try TestFolder()
        let mac = try await TestDevice("Mac", folder: folder.url)
        let (page, _) = try await mac.createPage("Notiz", texts: ["Eins"])
        let report = try await mac.sync()
        let device = mac.deviceID.uuidString
        #expect(try folder.files() == [
            "quill.json", "devices/\(device).json",
            "tree/\(device)/000000000001.changes",
            "pages/\(page.uuidString)/\(device)/000000000001.changes",
        ])
        #expect(report.conflicts.isEmpty && report.unreadable.isEmpty && report.postponed.isEmpty)
        // Dateinamen ohne Titel (ADR-026).
        #expect(try folder.files().allSatisfy { !$0.contains("Notiz") })
        // Ohne Änderung schreibt ein zweiter Abgleich nichts, auch nicht mit einer Seite
        // im Papierkorb (Datum und Stand beim Papierkorb bleiben beim Lesen gleich).
        let before = try folder.fingerprint()
        try await mac.sync()
        #expect(try folder.fingerprint() == before)
        try await mac.store.trash(page)
        try await mac.sync()
        let trashed = try folder.fingerprint()
        #expect(trashed.count == before.count + 1)
        try await mac.sync()
        #expect(try folder.fingerprint() == trashed)
    }

    @Test func pagesBlocksAndTreeReachTheOtherDevice() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let parent = try await a.store.createPage(title: "Projekte")
        let child = try await a.store.createPage(title: "Quill", in: parent)
        try await a.store.setIcon(child, to: "🪶")
        let rich = try RichText(runs: [.init(text: "fett", marks: ["bold"]), .init(text: " normal")]).encoded()
        let blocks = [
            BlockSnapshot(id: UUID(), kindRaw: BlockKind.heading1.rawValue, text: "Titel"),
            BlockSnapshot(id: UUID(), text: "fett normal", richText: rich),
            BlockSnapshot(id: UUID(), kindRaw: BlockKind.todo.rawValue, text: "Erledigt", properties: BlockProperties(indent: 1, isChecked: true)),
        ]
        try await a.store.applyEdits(child, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        try await a.sync()
        let progress = Mutex<[SyncProgress]>([])
        let report = try await b.sync { value in progress.withLock { $0.append(value) } }

        let quill = try await b.page(titled: "Quill")
        #expect(quill.parentID == parent)
        #expect(quill.icon == "🪶")
        let received = try await b.store.blocks(of: child)
        #expect(received.map(\.id) == blocks.map(\.id))
        #expect(received.map(\.text) == blocks.map(\.text))
        #expect(received.map(\.kindRaw) == blocks.map(\.kindRaw))
        #expect(received[2].properties == blocks[2].properties)
        #expect(RichText.decode(try #require(received[1].richText)) == RichText.decode(rich))
        #expect(report.changedPages.isSuperset(of: [parent, child]))
        // Fortschritt beim ersten Abgleich: zählt bis zum Ende, ohne Rückschritt.
        let values = progress.withLock { $0 }
        #expect(values.last.map { $0.done == $0.total } == true)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0.done <= $1.done })
        // B schreibt danach nur eigene Dateien (Gerät), keine Änderungen an A's Inhalt.
        #expect(try folder.files().filter { $0.contains(b.deviceID.uuidString) } == ["devices/\(b.deviceID.uuidString).json"])
    }

    // MARK: Ordnerwechsel (11.4)

    /// Mit einem anderen Ordner bleibt die Geschichte: Die erste eigene Datei je
    /// Dokument ist der ganze Stand, auch mit Beiträgen anderer Geräte aus dem
    /// vorherigen Ordner. Ein neues Gerät im neuen Ordner kann alte Stände abrufen.
    @Test func newFolderGetsTheWholeHistory() async throws {
        let first = try TestFolder()
        let a = try await TestDevice("A", folder: first.url)
        let c = try await TestDevice("C", folder: first.url)
        let (page, blocks) = try await a.createPage("Alt", texts: ["eins"])
        try await a.sync()
        let byA = try await pageVersion(a, page)
        try await c.sync()
        try await c.edit(page, blocks[0]) { $0.text = "zwei" }
        try await c.sync()
        try await a.sync()
        let byC = try await pageVersion(a, page)
        let oldTree = try TreeDocument(bytes: #require(try await a.store.syncState().tree)).version
        try await a.store.rename(page, to: "Neu")
        try await a.sync()

        // A wechselt in einen anderen Ordner, als neues Gerät.
        let second = try TestFolder()
        try await a.store.resetSyncCursors()
        try await a.store.setSyncDeviceID(UUID())
        let moved = SyncEngine(store: a.store, folder: second.url, gate: SyncGate(), deviceName: "A")
        let folderID = try await moved.sync(connectedFolderID: nil).folderID
        let written = try second.fingerprint()
        _ = try await moved.sync(connectedFolderID: folderID)
        #expect(try second.fingerprint().filter { !$0.key.hasPrefix("Quill/devices/") } == written.filter { !$0.key.hasPrefix("Quill/devices/") })

        let b = try await TestDevice("B", folder: second.url)
        try await b.sync()
        #expect(try await b.texts(of: "Neu") == ["zwei"])
        let document = try PageDocument(bytes: #require(try await b.store.syncPage(page)?.document))
        #expect(document.contains(byA) && document.contains(byC))
        #expect(try document.blocks(at: byA).map(\.text) == ["eins"])
        #expect(try document.blocks(at: byC).map(\.text) == ["zwei"])
        let tree = try TreeDocument(bytes: #require(try await b.store.syncState().tree))
        #expect(tree.contains(oldTree))

        // Danach geht es mit einzelnen Änderungen weiter, in beide Richtungen.
        try await b.edit(page, blocks[0]) { $0.text = "drei" }
        try await b.sync()
        _ = try await moved.sync(connectedFolderID: folderID)
        #expect(try await a.texts(of: "Neu") == ["drei"])
    }

    /// Wer eine Seite nur empfängt, schreibt keine Kopie davon in den Ordner.
    @Test func receivingDeviceWritesNoCopies() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, blocks) = try await a.createPage("Seite", texts: ["eins"])
        try await a.sync()
        try await b.sync()
        try await a.edit(page, blocks[0]) { $0.text = "zwei" }
        try await a.sync()
        try await b.sync()
        #expect(try await b.texts(of: "Seite") == ["zwei"])
        #expect(try folder.files().filter { $0.contains(b.deviceID.uuidString) } == ["devices/\(b.deviceID.uuidString).json"])
    }

    private func pageVersion(_ device: TestDevice, _ page: UUID) async throws -> DocumentVersion {
        try PageDocument(bytes: #require(try await device.store.syncPage(page)?.document)).version
    }

    // MARK: Fälle aus ADR-026

    @Test func concurrentTypingInTheSameBlockIsMerged() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Hallo Welt"])
        try await a.sync()
        try await b.sync()
        try await a.edit(page, blocks[0]) { $0.text = "Hallo schöne Welt" }
        try await b.edit(page, blocks[0]) { $0.text = "Hallo Welt!" }
        try await a.sync()
        try await b.sync()
        try await a.sync()
        #expect(try await a.texts(of: "Notiz") == ["Hallo schöne Welt!"])
        #expect(try await b.texts(of: "Notiz") == ["Hallo schöne Welt!"])
    }

    @Test func deletingAnEditedBlockKeepsItAsRestored() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Bleibt", "Umstritten", "Nur gelöscht"])
        try await a.sync()
        try await b.sync()
        try await a.store.applyEdits(page, BlockEdits(deletions: [blocks[1], blocks[2]]))
        try await b.edit(page, blocks[1]) { $0.text = "Umstritten, bearbeitet" }
        try await a.sync()
        let report = try await b.sync()
        try await a.sync()
        #expect(report.restoredBlocks == [blocks[1]])
        for device in [a, b] {
            let result = try await device.blocks(of: "Notiz")
            #expect(result.map(\.text) == ["Bleibt", "Umstritten, bearbeitet"], "\(device.name)")
            #expect(result.map(\.properties.isRestored) == [false, true], "\(device.name)")
        }
        // „Markierung entfernen“ auf einem Gerät gilt danach auf beiden (11.6).
        try await a.edit(page, blocks[1]) { $0.properties.isRestored = false }
        try await a.sync()
        try await b.sync()
        for device in [a, b] {
            #expect(try await device.blocks(of: "Notiz").map(\.properties.isRestored) == [false, false], "\(device.name)")
        }
    }

    @Test func twoValuesForTheSameFieldAreReportedAndKept() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Punkt"])
        try await a.sync()
        try await b.sync()
        try await a.edit(page, blocks[0]) { $0.kindRaw = BlockKind.todo.rawValue }
        try await b.edit(page, blocks[0]) { $0.kindRaw = BlockKind.heading2.rawValue }
        try await a.store.rename(page, to: "Notiz A")
        try await b.store.rename(page, to: "Notiz B")
        try await a.sync()
        let report = try await b.sync()
        let blockConflict = try #require(report.conflicts[page]?.first)
        #expect(blockConflict.objectID == blocks[0])
        #expect(blockConflict.field == "kind")
        #expect(Set(blockConflict.values) == [BlockKind.todo.rawValue, BlockKind.heading2.rawValue])
        let titleConflict = try #require(report.conflicts[SyncReport.treeID]?.first)
        #expect(titleConflict.objectID == page && titleConflict.field == "title")
        #expect(Set(titleConflict.values) == ["Notiz A", "Notiz B"])
        // Bis der Nutzer wählt, bleibt der Konflikt bei jedem Abgleich bestehen, auch
        // wenn beide Geräte ihren Stand danach mehrmals exportieren.
        for _ in 0..<3 {
            for device in [a, b] {
                let again = try await device.sync()
                #expect(Set(again.conflicts[page]?.first?.values ?? []) == Set(blockConflict.values), "\(device.name)")
                #expect(Set(again.conflicts[SyncReport.treeID]?.first?.values ?? []) == ["Notiz A", "Notiz B"], "\(device.name)")
            }
        }
    }

    @Test func choiceIsWrittenAsOwnFileAndResolvesOnBothDevices() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Punkt"])
        try await a.sync()
        try await b.sync()
        try await a.edit(page, blocks[0]) { $0.kindRaw = BlockKind.todo.rawValue }
        try await b.edit(page, blocks[0]) { $0.kindRaw = BlockKind.heading2.rawValue }
        try await a.store.rename(page, to: "Notiz A")
        try await b.store.rename(page, to: "Notiz B")
        try await a.sync()
        try await b.sync()
        let report = try await a.sync()
        // Jede Fassung nennt ihr Gerät, die Namen kommen aus `devices/`.
        #expect(report.devices == [a.deviceID: "A", b.deviceID: "B"])
        let kind = try #require(report.conflicts[page]?.first)
        #expect(kind.versions.map(\.device) == [b.deviceID, a.deviceID])
        let title = try #require(report.conflicts[SyncReport.treeID]?.first)
        #expect(title.versions.map(\.device) == [a.deviceID, b.deviceID])

        let filesBefore = try folder.files()
        await a.engine.choose(ConflictChoice(documentID: page, objectID: blocks[0], field: "kind", value: BlockKind.heading2.rawValue))
        await a.engine.choose(ConflictChoice(documentID: SyncReport.treeID, objectID: page, field: "title", value: "Notiz A"))
        let chosen = try await a.sync()
        #expect(chosen.conflicts.isEmpty)
        #expect(chosen.changedPages.contains(page))
        let added = try folder.files().subtracting(filesBefore)
        #expect(added == [
            "pages/\(page.uuidString)/\(a.deviceID.uuidString)/000000000003.changes",
            "tree/\(a.deviceID.uuidString)/000000000003.changes",
        ])
        let other = try await b.sync()
        #expect(other.conflicts.isEmpty)
        for device in [a, b] {
            #expect(try await device.blocks(of: "Notiz A").map(\.kindRaw) == [BlockKind.heading2.rawValue], "\(device.name)")
        }
        // Die Wahl ist verbraucht: Der nächste Abgleich schreibt nichts mehr.
        let settled = try folder.files()
        try await a.sync()
        #expect(try folder.files() == settled)
    }

    @Test func choiceIsDroppedWhenAnotherDeviceAlreadyChose() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Punkt"])
        try await a.sync()
        try await b.sync()
        try await a.edit(page, blocks[0]) { $0.kindRaw = BlockKind.todo.rawValue }
        try await b.edit(page, blocks[0]) { $0.kindRaw = BlockKind.heading2.rawValue }
        try await a.sync()
        try await b.sync()
        try await a.sync()
        await b.engine.choose(ConflictChoice(documentID: page, objectID: blocks[0], field: "kind", value: BlockKind.todo.rawValue))
        try await b.sync()
        let filesBefore = try folder.files()
        await a.engine.choose(ConflictChoice(documentID: page, objectID: blocks[0], field: "kind", value: BlockKind.heading2.rawValue))
        let report = try await a.sync()
        #expect(report.conflicts.isEmpty)
        #expect(try folder.files() == filesBefore)
        #expect(try await a.blocks(of: "Notiz").map(\.kindRaw) == [BlockKind.todo.rawValue])
    }

    @Test func storedConflictsMatchTheLastSyncWithoutWriting() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Punkt"])
        try await a.sync()
        try await b.sync()
        try await a.edit(page, blocks[0]) { $0.kindRaw = BlockKind.todo.rawValue }
        try await b.edit(page, blocks[0]) { $0.kindRaw = BlockKind.heading2.rawValue }
        try await a.store.rename(page, to: "Hier")
        try await b.store.rename(page, to: "Dort")
        try await a.sync()
        try await b.sync()
        let report = try await a.sync()
        #expect(Set(report.conflicts.keys) == [page, SyncReport.treeID])

        // Wie nach einem Neustart: neue Engine, pausiert, nur der Store.
        let filesBefore = try folder.files()
        let gate = SyncGate(paused: true)
        let restarted = SyncEngine(store: a.store, folder: folder.url, gate: gate, deviceName: "A", files: TestFileAccess())
        let stored = try #require(try await restarted.storedConflicts(folderID: report.folderID))
        #expect(stored.conflicts == report.conflicts)
        #expect(stored.devices == report.devices)
        #expect(try folder.files() == filesBefore)
        // Ohne Geräte-ID (Sync nie eingeschaltet) nichts.
        let fresh = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let never = SyncEngine(store: fresh, folder: folder.url, gate: gate, deviceName: "C", files: TestFileAccess())
        #expect(try await never.storedConflicts(folderID: report.folderID) == nil)
    }

    @Test func unreadableFileIsQuarantinedAndLeftUntouched() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        try await a.createPage("Von A", texts: ["Inhalt"])
        try await a.sync()
        // Ein drittes Gerät mit kaputter Datei im Seitenbaum.
        let broken = folder.layout.tree(device: UUID())
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        let brokenFile = SyncFolderLayout.changes(1, in: broken)
        try Data("kein Automerge".utf8).write(to: brokenFile)
        let report = try await b.sync()
        #expect(report.unreadable.map(\.path) == [String(brokenFile.path(percentEncoded: false).dropFirst(folder.layout.root.path(percentEncoded: false).count))])
        #expect(try Data(contentsOf: brokenFile) == Data("kein Automerge".utf8))
        // Der Rest kommt trotzdem an, und der nächste Abgleich versucht es erneut.
        #expect(try await b.texts(of: "Von A") == ["Inhalt"])
        #expect(try await b.sync().unreadable.count == 1)
    }

    @Test func foreignQuillFolderIsOnlyMergedAfterConfirmation() async throws {
        let folder = try TestFolder()
        let other = try await TestDevice("Fremd", folder: folder.url)
        try await other.createPage("Fremde Seite")
        try await other.sync()
        let mine = try await TestDevice("Mein Mac", folder: folder.url)
        try await mine.createPage("Meine Seite")
        let before = try folder.fingerprint()

        // Verbunden mit einem anderen Ordner: Rückfrage, nichts geschrieben oder gelesen.
        await #expect(throws: SyncFailure.unknownFolder(try #require(other.files.connected))) {
            try await mine.engine.sync(connectedFolderID: UUID())
        }
        // Noch nie verbunden: auch dann erst nach Rückfrage.
        await #expect(throws: SyncFailure.unknownFolder(try #require(other.files.connected))) {
            try await mine.engine.sync(connectedFolderID: nil)
        }
        #expect(try folder.fingerprint() == before)
        #expect(try await mine.store.pageSnapshots().map(\.title) == ["Meine Seite"])

        // Nach Zustimmung: zusammengeführt.
        _ = try await mine.engine.sync(connectedFolderID: other.files.connected)
        #expect(Set(try await mine.store.pageSnapshots().map(\.title)) == ["Meine Seite", "Fremde Seite"])
    }

    @Test func connectedFolderWithoutManifestIsNotRecreated() async throws {
        let folder = try TestFolder()
        let mac = try await TestDevice("Mac", folder: folder.url)
        await #expect(throws: SyncFailure.folderMissing) {
            try await mac.engine.sync(connectedFolderID: UUID())
        }
        #expect(try folder.fingerprint().isEmpty)
    }

    @Test func newerFolderFormatIsNotWritten() async throws {
        let folder = try TestFolder()
        let mac = try await TestDevice("Mac", folder: folder.url)
        try FileManager.default.createDirectory(at: folder.layout.root, withIntermediateDirectories: true)
        try Data(#"{"format": 2}"#.utf8).write(to: folder.layout.manifest)
        let before = try folder.fingerprint()
        await #expect(throws: SyncFailure.newerFormat(2)) {
            try await mac.engine.sync(connectedFolderID: nil)
        }
        #expect(try folder.fingerprint() == before)
    }

    @Test func fileNotYetDownloadedIsRequestedAndAppliedLater() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Erste Fassung"])
        try await a.sync()
        try await b.sync()
        try await a.edit(page, blocks[0]) { $0.text = "Zweite Fassung" }
        try await a.sync()
        let pending = "000000000002.changes"
        b.files.state.withLock { $0.notDownloaded = [pending] }

        let waiting = try await b.sync()
        #expect(try await b.texts(of: "Notiz") == ["Erste Fassung"])
        #expect(b.files.state.withLock { $0.downloadRequests }.contains(pending))
        #expect(waiting.waitingForDownload.contains { $0.hasSuffix(pending) })

        b.files.state.withLock { $0.notDownloaded = [] }
        try await b.sync()
        #expect(try await b.texts(of: "Notiz") == ["Zweite Fassung"])
    }

    @Test func iCloudPlaceholderNamesAreRecognized() {
        #expect(CoordinatedFileAccess.placeholderTarget(".000000000003.changes.icloud") == "000000000003.changes")
        #expect(CoordinatedFileAccess.placeholderTarget("000000000003.changes") == nil)
        #expect(CoordinatedFileAccess.placeholderTarget("..icloud") == nil)
    }

    // MARK: Papierkorb und Löschen (ADR-029)

    @Test func permanentlyDeletedPageLandsInTheOtherTrashFirst() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, _) = try await a.createPage("Alt", texts: ["Inhalt"])
        try await a.sync()
        try await b.sync()
        try await a.store.trash(page)
        try await a.store.emptyTrash()
        try await a.sync()
        try await b.sync()
        // Auf B nur im Papierkorb, mit Inhalt.
        let onB = try await b.page(titled: "Alt")
        #expect(onB.trashedAt != nil)
        #expect(try await b.texts(of: "Alt") == ["Inhalt"])
        // Weg erst nach „Papierkorb leeren“ auf B; danach kommt sie nirgends zurück.
        try await b.store.emptyTrash()
        try await b.sync()
        try await a.sync()
        try await b.sync()
        #expect(try await a.store.pageSnapshots().isEmpty)
        #expect(try await b.store.pageSnapshots().isEmpty)
    }

    @Test func trashedPageStaysWhereItWasEditedMeanwhile() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (edited, blocks) = try await a.createPage("Bearbeitet", texts: ["Alt"])
        let (untouched, _) = try await a.createPage("Unberührt", texts: ["Alt"])
        try await a.sync()
        try await b.sync()
        try await a.store.trash(edited)
        try await a.store.trash(untouched)
        try await b.edit(edited, blocks[0]) { $0.text = "Neu auf B" }
        try await a.sync()
        let report = try await b.sync()
        try await a.sync()
        #expect(report.restoredPages == [edited])
        for device in [a, b] {
            let page = try await device.page(titled: "Bearbeitet")
            #expect(page.trashedAt == nil && page.isRestored, "\(device.name)")
            #expect(try await device.texts(of: "Bearbeitet") == ["Neu auf B"], "\(device.name)")
            #expect(try await device.page(titled: "Unberührt").trashedAt != nil, "\(device.name)")
        }
        _ = untouched
        // „Markierung entfernen“ auf einem Gerät gilt danach auf beiden (11.6).
        try await b.store.setRestored(edited, false)
        try await b.sync()
        try await a.sync()
        for device in [a, b] {
            #expect(try await !device.page(titled: "Bearbeitet").isRestored, "\(device.name)")
        }
    }

    // MARK: Pausieren, Abbruch, Bilder

    @Test func pausingStopsWritingToTheFolderImmediately() async throws {
        let folder = try TestFolder()
        let mac = try await TestDevice("Mac", folder: folder.url)
        for index in 1...3 { try await mac.createPage("Seite \(index)", texts: ["Text"]) }
        let gate = mac.gate
        // Mitten im Abgleich pausieren: nach der ersten Seiten-Datei.
        mac.files.state.withLock { state in
            state.onCreate = { url in
                if SyncFolderLayout.changesNumber(url.lastPathComponent) != nil, url.path().contains("/pages/") { gate.pause() }
            }
        }
        await #expect(throws: SyncFailure.paused) { try await mac.sync() }
        let pageFiles = try folder.files().filter { $0.hasPrefix("pages/") }
        #expect(pageFiles.count == 1)
        // Pausiert: kein Abgleich schreibt etwas.
        let before = try folder.fingerprint()
        await #expect(throws: SyncFailure.paused) { try await mac.engine.sync(connectedFolderID: mac.files.connected) }
        #expect(try folder.fingerprint() == before)
        // Fortsetzen: alles kommt nach, nichts doppelt.
        mac.files.state.withLock { $0.onCreate = nil }
        gate.resume()
        try await mac.sync()
        #expect(try folder.files().filter { $0.hasPrefix("pages/") }.count == 3)
        #expect(try folder.files().filter { $0.hasPrefix("tree/") }.count == 1)
    }

    @Test func abortBetweenFolderAndStoreDoesNotDuplicateText() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Anfang"])
        try await a.sync()
        try await b.sync()
        try await a.edit(page, blocks[0]) { $0.text = "Anfang und mehr" }
        // Nach dem Schreiben der eigenen Datei bricht der Abgleich ab, bevor der Store speichert.
        struct Abort: Error {}
        let pageFolder = folder.layout.pages.appending(path: page.uuidString, directoryHint: .isDirectory).standardizedFileURL
        a.files.state.withLock { state in
            state.onContents = { url in if url.standardizedFileURL == pageFolder { throw Abort() } }
        }
        await #expect(throws: Abort.self) { try await a.sync() }
        a.files.state.withLock { $0.onContents = nil }
        try await a.edit(page, blocks[0]) { $0.text = "Anfang und mehr!" }
        try await a.sync()
        try await b.sync()
        #expect(try await b.texts(of: "Notiz") == ["Anfang und mehr!"])
        #expect(try await a.texts(of: "Notiz") == ["Anfang und mehr!"])
    }

    @Test func imagesTravelAsFilesNamedByContent() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let png = try TestImage.png(red: 0.8)
        let page = try await a.store.createPage(title: "Bild")
        let image = try await a.store.importImage(png)
        let block = BlockSnapshot(id: UUID(), kindRaw: BlockKind.image.rawValue, properties: BlockProperties(assetID: image.assetID))
        try await a.store.applyEdits(page, BlockEdits(upserts: [block], order: [block.id]))
        let stored = try #require(try await a.store.imageData(image.assetID))
        try await a.sync()
        let name = "assets/\(SyncFolderLayout.sha256(stored.data)).png"
        #expect(try folder.files().contains(name))
        try await b.sync()
        let received = try #require(try await b.blocks(of: "Bild").first)
        #expect(received.properties.assetID == image.assetID)
        let onB = try #require(try await b.store.imageData(image.assetID))
        #expect(onB.data == stored.data)
        #expect(onB.uti == stored.uti)
    }

    @Test func pageWaitsForAnImageNotYetDownloaded() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let page = try await a.store.createPage(title: "Bild")
        let image = try await a.store.importImage(try TestImage.png(red: 0.3))
        let block = BlockSnapshot(id: UUID(), kindRaw: BlockKind.image.rawValue, properties: BlockProperties(assetID: image.assetID))
        try await a.store.applyEdits(page, BlockEdits(upserts: [block], order: [block.id]))
        try await a.sync()
        let file = try #require(try folder.files().first { $0.hasPrefix("assets/") })
        b.files.state.withLock { $0.notDownloaded = [String(file.dropFirst("assets/".count))] }
        try await b.sync()
        #expect(try await b.blocks(of: "Bild").isEmpty)
        b.files.state.withLock { $0.notDownloaded = [] }
        try await b.sync()
        #expect(try await b.blocks(of: "Bild").first?.properties.assetID == image.assetID)
    }
}
