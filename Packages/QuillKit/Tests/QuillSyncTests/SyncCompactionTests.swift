import Foundation
import QuillModel
@testable import QuillSync
import Synchronization
import Testing

/// Verdichten der eigenen Dateien zu `<Nr>.snapshot` (ADR-026, ADR-029): erst schreiben,
/// dann nur eigene Dateien löschen; andere Geräte lesen die verdichtete Datei oder,
/// solange sie fehlt, die alten Dateien. Nur Stores im Arbeitsspeicher und Wegwerf-Ordner.
@Suite("Abgleich: verdichten")
struct SyncCompactionTests {
    /// Eigene Dateien eines Geräts für eine Seite, nur die Namen.
    func ownFiles(_ folder: borrowing TestFolder, page: UUID, device: TestDevice) throws -> [String] {
        try folder.files().filter { $0.hasPrefix("pages/\(page.uuidString)/\(device.deviceID.uuidString)/") }
            .map { ($0 as NSString).lastPathComponent }.sorted()
    }

    /// `count` Mal den Text ändern und abgleichen: je eine eigene Datei.
    func edit(_ device: TestDevice, _ page: UUID, _ block: UUID, times count: Int, from start: Int = 1) async throws {
        for index in start..<(start + count) {
            try await device.edit(page, block) { $0.text = "Fassung \(index)" }
            try await device.sync()
        }
    }

    /// Erste Datei (ganzer Stand) und genau `compactAfter` eigene Dateien danach.
    func compacted(_ folder: borrowing TestFolder, _ a: TestDevice) async throws -> (page: UUID, block: UUID, early: DocumentVersion) {
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Anfang"])
        try await a.sync()
        let early = try PageDocument(bytes: #require(try await a.store.syncPage(page)?.document)).version
        try await edit(a, page, blocks[0], times: SyncEngine.compactAfter - 1)
        #expect(try ownFiles(folder, page: page, device: a).count == SyncEngine.compactAfter)
        try await edit(a, page, blocks[0], times: 1, from: SyncEngine.compactAfter)
        return (page, blocks[0], early)
    }

    @Test func fiftyOwnFilesBecomeOneSnapshotAndEveryDeviceCatchesUp() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let before = try await TestDevice("Vorher", folder: folder.url)
        let midway = try await TestDevice("Mittendrin", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Anfang"])
        try await a.sync()
        try await before.sync()
        let early = try PageDocument(bytes: #require(try await a.store.syncPage(page)?.document)).version
        try await edit(a, page, blocks[0], times: 20)
        try await midway.sync()
        try await edit(a, page, blocks[0], times: SyncEngine.compactAfter - 20)
        // 1 = erste Datei, 2…51 = 50 eigene Dateien → 52 ersetzt alle.
        #expect(try ownFiles(folder, page: page, device: a) == ["000000000052.snapshot"])
        try await edit(a, page, blocks[0], times: 1, from: SyncEngine.compactAfter + 1)
        #expect(try ownFiles(folder, page: page, device: a) == ["000000000052.snapshot", "000000000053.changes"])

        let fresh = try await TestDevice("Neu", folder: folder.url)
        for device in [before, midway, fresh] {
            let report = try await device.sync()
            #expect(report.unreadable.isEmpty && report.waitingForDownload.isEmpty && report.gaps.isEmpty, "\(device.name)")
            #expect(try await device.texts(of: "Notiz") == ["Fassung \(SyncEngine.compactAfter + 1)"], "\(device.name)")
            // Die Geschichte reist mit: Auch ein neues Gerät kennt den ersten Stand.
            let document = try PageDocument(bytes: #require(try await device.store.syncPage(page)?.document))
            #expect(document.contains(early), "\(device.name)")
            #expect(try document.blocks(at: early).map(\.text) == ["Anfang"], "\(device.name)")
        }
        // Nur eigene Dateien gelöscht.
        #expect(a.files.state.withLock { $0.deleted }.count == 51)
        for device in [before, midway, fresh] { #expect(device.files.state.withLock { $0.deleted }.isEmpty) }
    }

    @Test func theTreeIsCompactedToo() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, _) = try await a.createPage("Titel 0")
        try await a.sync()
        try await b.sync()
        for index in 1...SyncEngine.compactAfter {
            try await a.store.rename(page, to: "Titel \(index)")
            try await a.sync()
        }
        let tree = try folder.files().filter { $0.hasPrefix("tree/\(a.deviceID.uuidString)/") }
        #expect(tree == ["tree/\(a.deviceID.uuidString)/000000000052.snapshot"])
        try await b.sync()
        #expect(try await b.store.pageSnapshots().map(\.title) == ["Titel \(SyncEngine.compactAfter)"])
    }

    @Test func folderWithAFullStateAsFirstChangesFileIsReadAndCleanedUp() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Anfang"])
        try await a.sync()
        // Format bis 11.6: die erste Datei hieß `<Nr>.changes`, mit ganzem Stand.
        let pageFolder = folder.layout.page(page, device: a.deviceID)
        try FileManager.default.moveItem(
            at: SyncFolderLayout.snapshot(1, in: pageFolder), to: SyncFolderLayout.changes(1, in: pageFolder)
        )
        let b = try await TestDevice("B", folder: folder.url)
        try await b.sync()
        #expect(try await b.texts(of: "Notiz") == ["Anfang"])
        // 1…50 sind nun alle `.changes`: Die verdichtete Datei 51 ersetzt sie.
        try await edit(a, page, blocks[0], times: SyncEngine.compactAfter - 1)
        #expect(try ownFiles(folder, page: page, device: a) == ["000000000051.snapshot"])
        try await b.sync()
        #expect(try await b.texts(of: "Notiz") == ["Fassung \(SyncEngine.compactAfter - 1)"])
    }

    // MARK: Noch nicht geladen, unlesbar, Lücke (ADR-026)

    @Test func snapshotNotYetDownloadedFallsBackToTheOldFilesOrWaits() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Anfang"])
        try await a.sync()
        let late = try await TestDevice("Spät", folder: folder.url)
        try await late.sync()
        try await edit(a, page, blocks[0], times: SyncEngine.compactAfter - 1)
        // Die alten Dateien sichern: Beim ersten Gerät kommt das Löschen später an.
        let pageFolder = folder.layout.page(page, device: a.deviceID)
        let copy = FileManager.default.temporaryDirectory.appending(path: "QuillSyncAlt-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: pageFolder, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        try await edit(a, page, blocks[0], times: 1, from: SyncEngine.compactAfter)
        let snapshot = "000000000052.snapshot"

        // Platzhalter, alte Dateien schon weg → warten, anfordern, keine Lücke.
        try await edit(a, page, blocks[0], times: 1, from: SyncEngine.compactAfter + 1)
        late.files.state.withLock { $0.notDownloaded = [snapshot] }
        var report = try await late.sync()
        #expect(report.waitingForDownload == ["pages/\(page.uuidString)/\(a.deviceID.uuidString)/\(snapshot)"])
        #expect(report.gaps.isEmpty)
        #expect(late.files.state.withLock { $0.downloadRequests }.contains(snapshot))
        #expect(try await late.texts(of: "Notiz") == ["Anfang"])

        // Alte Dateien noch da (Löschen noch nicht angekommen) → weiter mit ihnen.
        for name in try FileManager.default.contentsOfDirectory(atPath: copy.path()) where name.hasSuffix(".changes") {
            let target = pageFolder.appending(path: name)
            if !FileManager.default.fileExists(atPath: target.path()) { try FileManager.default.copyItem(at: copy.appending(path: name), to: target) }
        }
        report = try await late.sync()
        #expect(report.waitingForDownload.count == 1)
        #expect(try await late.texts(of: "Notiz") == ["Fassung \(SyncEngine.compactAfter - 1)"])

        // Geladen: Rest aus der verdichteten Datei, ohne Verlust.
        late.files.state.withLock { $0.notDownloaded = [] }
        report = try await late.sync()
        #expect(report.waitingForDownload.isEmpty && report.unreadable.isEmpty)
        #expect(try await late.texts(of: "Notiz") == ["Fassung \(SyncEngine.compactAfter + 1)"])
        // Die alten Dateien von A räumt nur A selbst weg, nie ein anderes Gerät.
        #expect(late.files.state.withLock { $0.deleted }.isEmpty)
        #expect(FileManager.default.fileExists(atPath: SyncFolderLayout.changes(2, in: pageFolder).path()))
    }

    @Test func unreadableSnapshotIsReportedKeptAndRetried() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, _, _) = try await compacted(folder, a)
        let snapshot = SyncFolderLayout.snapshot(52, in: folder.layout.page(page, device: a.deviceID))
        let good = try Data(contentsOf: snapshot)
        try Data("kaputt".utf8).write(to: snapshot)

        var report = try await b.sync()
        #expect(report.unreadable.map(\.path) == ["pages/\(page.uuidString)/\(a.deviceID.uuidString)/000000000052.snapshot"])
        #expect(report.gaps.isEmpty)
        // Liegt unverändert da; B löscht nichts und übernimmt nichts von A's Seite.
        #expect(try Data(contentsOf: snapshot) == Data("kaputt".utf8))
        #expect(b.files.state.withLock { $0.deleted }.isEmpty)
        #expect(try await b.texts(of: "Notiz").isEmpty)

        // Repariert: der nächste Abgleich nimmt sie.
        try good.write(to: snapshot)
        report = try await b.sync()
        #expect(report.unreadable.isEmpty)
        #expect(try await b.texts(of: "Notiz") == ["Fassung \(SyncEngine.compactAfter)"])
    }

    @Test func gapWithoutSnapshotIsReportedAfterAnHourWithDeviceAndPage() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let clock = Mutex(Date(timeIntervalSince1970: 1_900_000_000))
        let b = try await TestDevice("B", folder: folder.url) { clock.withLock { $0 } }
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Anfang"])
        try await a.sync()
        try await b.sync()
        try await edit(a, page, blocks[0], times: SyncEngine.compactAfter)
        try await edit(a, page, blocks[0], times: 1, from: SyncEngine.compactAfter + 1)
        // Löschen ist bei B angekommen, die verdichtete Datei noch nicht: 1 gelesen, 53 da.
        b.files.state.withLock { $0.invisible = ["000000000052.snapshot"] }
        let start = clock.withLock { $0 }

        var report = try await b.sync()
        #expect(report.gaps.isEmpty)
        clock.withLock { $0 = start.addingTimeInterval(SyncEngine.gapReportDelay - 60) }
        report = try await b.sync()
        #expect(report.gaps.isEmpty)
        clock.withLock { $0 = start.addingTimeInterval(SyncEngine.gapReportDelay) }
        report = try await b.sync()
        #expect(report.gaps == [SyncGap(document: page, device: a.deviceID, since: start)])
        #expect(try await b.texts(of: "Notiz") == ["Anfang"])

        // Angekommen: weiter, Lücke vergessen.
        b.files.state.withLock { $0.invisible = [] }
        report = try await b.sync()
        #expect(report.gaps.isEmpty)
        #expect(try await b.texts(of: "Notiz") == ["Fassung \(SyncEngine.compactAfter + 1)"])
        b.files.state.withLock { $0.invisible = ["000000000052.snapshot"] }
        clock.withLock { $0 = start.addingTimeInterval(10 * SyncEngine.gapReportDelay) }
        #expect(try await b.sync().gaps.isEmpty)
    }

    // MARK: Eigene Dateien noch nicht übernommen (Review)

    /// Sync-Dokument und gelesene Dateien im Store.
    struct StoreState {
        var document: Data
        var cursors: Data
    }

    func storeState(_ device: TestDevice, _ page: UUID) async throws -> StoreState {
        StoreState(
            document: try #require(try await device.store.syncPage(page)?.document),
            cursors: try #require(try await device.store.syncState().cursors)
        )
    }

    /// Wie nach einem Abbruch zwischen Ordner und Store: Die Blöcke sind gespeichert,
    /// Dokument und gelesene Dateien stehen noch auf `old`, die eigenen Dateien danach
    /// liegen nur im Ordner.
    func rollBack(_ device: TestDevice, _ page: UUID, to old: StoreState) async throws {
        let current = try await device.store.blocks(of: page)
        #expect(try await device.store.applySyncPage(page, expected: current, edits: BlockEdits(), document: old.document, cursors: old.cursors) != nil)
    }

    /// Eine eigene Datei ist noch nicht geladen (iCloud hat sie ausgelagert), der Store
    /// kennt sie nicht. Verdichtet und gelöscht wird erst, wenn alle da sind.
    @Test func ownFilesNotYetReadAreNeverCompactedAway() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Anfang"])
        try await a.sync()
        try await edit(a, page, blocks[0], times: 4)
        let old = try await storeState(a, page)
        let extra = BlockSnapshot(id: UUID(), text: "Nur in Datei 6")
        try await a.store.applyEdits(page, BlockEdits(upserts: [extra], order: [blocks[0], extra.id]))
        try await a.sync()
        let withFile6 = try PageDocument(bytes: #require(try await a.store.syncPage(page)?.document)).version
        try await edit(a, page, blocks[0], times: 5, from: 5)
        #expect(try ownFiles(folder, page: page, device: a).last == "000000000011.changes")
        try await b.sync()

        try await rollBack(a, page, to: old)
        a.files.state.withLock { $0.notDownloaded = ["000000000006.changes"] }
        try await edit(a, page, blocks[0], times: SyncEngine.compactAfter + 5, from: 100)
        #expect(a.files.state.withLock { $0.deleted }.isEmpty)
        #expect(try ownFiles(folder, page: page, device: a).filter { $0.hasSuffix(".snapshot") } == ["000000000001.snapshot"])
        #expect(FileManager.default.fileExists(atPath: SyncFolderLayout.changes(6, in: folder.layout.page(page, device: a.deviceID)).path()))

        // Geladen: alles übernommen, dann verdichtet, ohne neue Änderung auf der Seite
        // (fällig wird sie über den eigenen Ordner).
        try await a.sync()
        let settled = try folder.fingerprint()
        try await a.sync()
        #expect(try folder.fingerprint() == settled)
        a.files.state.withLock { $0.notDownloaded = [] }
        try await a.sync()
        let files = try ownFiles(folder, page: page, device: a)
        #expect(files.count == 1 && files[0].hasSuffix(".snapshot"), "\(files)")
        #expect(try await a.texts(of: "Notiz").contains("Nur in Datei 6"))
        // Datei 6 selbst ist nachgelesen, nicht nur ihr Inhalt aus dem Store neu angelegt.
        #expect(try PageDocument(bytes: #require(try await a.store.syncPage(page)?.document)).contains(withFile6))
        let fresh = try await TestDevice("Neu", folder: folder.url)
        try await fresh.sync()
        #expect(try await fresh.texts(of: "Notiz") == a.texts(of: "Notiz"))
        #expect(try await fresh.texts(of: "Notiz").contains("Nur in Datei 6"))
        // B kannte Datei 6 schon und kommt auf denselben Stand. (Den Block gibt es dabei im
        // Dokument zweimal, weil der Store ihn neu angelegt hat, solange Datei 6 fehlte;
        // das zeigt die Seite als Konflikt zur Wahl, unabhängig vom Verdichten.)
        try await b.sync()
        #expect(try await b.texts(of: "Notiz") == a.texts(of: "Notiz"))
    }

    /// `synced` trifft `updatedAt` nach dem Speichern genau; ältere, auf Sekunden
    /// gerundete Daten werden noch gelesen.
    @Test func cursorsKeepExactDates() throws {
        var cursors = SyncCursors()
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000.123456789)
        cursors.synced["Seite"] = date
        cursors.gaps["Seite", default: [:]]["Gerät"] = date
        let decoded = SyncCursors(data: try cursors.encoded())
        #expect(decoded == cursors)
        let old = Data(#"{"read":{"tree":{"A":3}},"synced":{"Seite":"2026-10-21T10:00:00Z"}}"#.utf8)
        #expect(SyncCursors(data: old).last("tree", device: UUID()) == 0)
        #expect(SyncCursors(data: old).read["tree"]?["A"] == 3)
        #expect(SyncCursors(data: old).synced["Seite"] != nil)
    }

    /// Fehlt dem Store die gelesene Nummer eigener Dateien, wird die Seite fällig, auch
    /// ohne Änderung, und holt sie nach.
    @Test func missingOwnFilesMakeThePageDue() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Anfang"])
        try await a.sync()
        try await edit(a, page, blocks[0], times: 3)
        var cursors = SyncCursors(data: try await a.store.syncState().cursors)
        #expect(cursors.last(page.uuidString, device: a.deviceID) == 4)
        cursors.setLast(2, page.uuidString, device: a.deviceID)
        try await a.store.saveSyncCursors(cursors.encoded())
        try await a.sync()
        #expect(SyncCursors(data: try await a.store.syncState().cursors).last(page.uuidString, device: a.deviceID) == 4)
    }

    /// Dokument noch nicht im Ordner (gelesene Dateien vergessen) und eine eigene Datei
    /// fehlt: Die erste Datei mit ganzem Stand ist eine gewöhnliche, keine verdichtete.
    @Test func firstFileIsNoSnapshotWhileOwnFilesAreMissing() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Anfang"])
        try await a.sync()
        let document = try #require(try await a.store.syncPage(page)?.document)
        try await edit(a, page, blocks[0], times: 3)
        let current = try await a.store.blocks(of: page)
        #expect(try await a.store.applySyncPage(page, expected: current, edits: BlockEdits(), document: document, cursors: SyncCursors().encoded()) != nil)
        a.files.state.withLock { $0.notDownloaded = ["000000000003.changes"] }
        try await a.sync()
        #expect(try ownFiles(folder, page: page, device: a) == [
            "000000000001.snapshot", "000000000002.changes", "000000000003.changes", "000000000004.changes", "000000000005.changes",
        ])
    }

    /// Abbruch zwischen Schreiben und Löschen, dazu ein Store von vorher, und die
    /// verdichtete und eine alte Datei sind noch nicht geladen: kein Aufräumen.
    @Test func cleanupWaitsUntilAllOwnFilesAreRead() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Anfang"])
        try await a.sync()
        let old = try await storeState(a, page)
        try await edit(a, page, blocks[0], times: SyncEngine.compactAfter - 1)
        struct Abort: Error {}
        a.files.state.withLock { $0.onDelete = { _ in throw Abort() } }
        await #expect(throws: Abort.self) { try await self.edit(a, page, blocks[0], times: 1, from: SyncEngine.compactAfter) }
        a.files.state.withLock { $0.onDelete = nil }
        #expect(try ownFiles(folder, page: page, device: a).count == SyncEngine.compactAfter + 2)

        try await rollBack(a, page, to: old)
        a.files.state.withLock { $0.notDownloaded = ["000000000052.snapshot", "000000000030.changes"] }
        let before = try ownFiles(folder, page: page, device: a)
        try await a.sync()
        try await a.sync()
        #expect(a.files.state.withLock { $0.deleted }.isEmpty)
        #expect(Set(before).isSubset(of: Set(try ownFiles(folder, page: page, device: a))))

        a.files.state.withLock { $0.notDownloaded = [] }
        try await a.sync()
        #expect(try ownFiles(folder, page: page, device: a).allSatisfy { !$0.hasPrefix("0000000000") || Int($0.prefix(12))! >= 52 })
        #expect(try await a.texts(of: "Notiz") == ["Fassung \(SyncEngine.compactAfter)"])
    }

    // MARK: Pause, Abbruch, fremde Dateien

    @Test func pausedNothingIsCompactedOrDeleted() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Anfang"])
        try await a.sync()
        try await edit(a, page, blocks[0], times: SyncEngine.compactAfter - 1)
        try await a.edit(page, blocks[0]) { $0.text = "Pausiert" }
        // Pausieren, während die 50. eigene Datei entsteht: Verdichten darf danach nicht mehr.
        let gate = a.gate
        a.files.state.withLock { state in
            state.onCreate = { url in if SyncFolderLayout.changesNumber(url.lastPathComponent) == 51 { gate.pause() } }
        }
        let before = try folder.fingerprint()
        await #expect(throws: SyncFailure.paused) { try await a.sync() }
        let after = try folder.fingerprint()
        // Nur die Datei mit der Änderung kam dazu, keine verdichtete, nichts ist weg.
        #expect(Set(after.keys).subtracting(before.keys).map { ($0 as NSString).lastPathComponent } == ["000000000051.changes"])
        #expect(a.files.state.withLock { $0.deleted }.isEmpty)
        await #expect(throws: SyncFailure.paused) { try await a.sync() }
        #expect(try folder.fingerprint() == after)
    }

    @Test func abortBetweenWritingAndDeletingIsCleanedUpNextTime() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Anfang"])
        try await a.sync()
        let (other, _) = try await b.createPage("Von B", texts: ["B"])
        try await b.sync()
        try await a.sync()
        try await edit(a, page, blocks[0], times: SyncEngine.compactAfter - 1)
        struct Abort: Error {}
        a.files.state.withLock { $0.onDelete = { _ in throw Abort() } }
        await #expect(throws: Abort.self) {
            try await a.edit(page, blocks[0]) { $0.text = "Zuletzt" }
            try await a.sync()
        }
        #expect(try ownFiles(folder, page: page, device: a).count == SyncEngine.compactAfter + 2)
        #expect(try ownFiles(folder, page: page, device: a).last == "000000000052.snapshot")
        let foreign = try folder.files().filter { $0.contains(b.deviceID.uuidString) }

        a.files.state.withLock { $0.onDelete = nil }
        try await a.sync()
        #expect(try ownFiles(folder, page: page, device: a) == ["000000000052.snapshot"])
        // Dateien von B bleiben, auch die von B's Seite im Ordner von A's Seite nie berührt.
        #expect(try folder.files().filter { $0.contains(b.deviceID.uuidString) } == foreign)
        #expect(a.files.state.withLock { $0.deleted }.allSatisfy { !$0.contains(b.deviceID.uuidString) })
        _ = other
        try await b.sync()
        #expect(try await b.texts(of: "Notiz") == ["Zuletzt"])
    }
}
