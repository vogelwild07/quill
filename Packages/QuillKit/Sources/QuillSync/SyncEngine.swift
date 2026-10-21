import Foundation
import QuillModel
import UniformTypeIdentifiers

/// Abgleich zwischen dem Store und dem Sync-Ordner (ADR-026, ADR-029).
///
/// Je Dokument (eine Seite oder der Seitenbaum):
/// 1. Dokument aus dem Store laden und eigene Dateien nachlesen, die der Store noch
///    nicht kennt (nach einem Abbruch zwischen Ordner und Store).
/// 2. Den Stand des Stores ins Dokument übernehmen und die neuen Änderungen als
///    nächste eigene Datei anhängen. So steht jede lokale Änderung zuerst im Dokument,
///    bevor fremde Änderungen dazukommen.
/// 3. Neue Dateien der anderen Geräte übernehmen, der Reihe nach, ohne Lücke.
/// 4. Was sich dadurch geändert hat, in den Store schreiben, zusammen mit dem Dokument
///    und den gelesenen Dateien. Hat der Nutzer inzwischen gespeichert, wird nichts
///    geschrieben, und der nächste Abgleich nimmt seine Änderung mit.
///
/// Seiten kommen vor dem Seitenbaum dran, damit „Papierkorb gegen Bearbeiten“ die
/// eigenen Bearbeitungen schon im Seiten-Dokument sieht.
public actor SyncEngine {
    public let layout: SyncFolderLayout
    private let store: PageStore
    private let files: any SyncFileAccess
    private let gate: SyncGate
    private let deviceName: String
    private var running: Task<SyncReport, any Error>?

    // Zustand eines Abgleichs
    private var device = UUID()
    private var cursors = SyncCursors()
    private var savedCursors = SyncCursors()
    private var report = SyncReport(folderID: UUID())
    private var assetNames: Set<String> = []
    private var updateDates: [UUID: Date] = [:]
    /// Wahl des Nutzers je Dokument, bis der nächste Abgleich sie schreibt (`choose(_:)`).
    private var choices: [UUID: [ConflictChoice]] = [:]
    #if DEBUG || QUILL_SYNCTEST
    /// Nur für Tests (Fall 12 in `docs/synctest.md`, `SyncTwoAppsUITests`): Der Abgleich
    /// hält vor dem Schreiben der n-ten Seite in den Store an, bis die App endet. Dann
    /// stehen die Dateien schon im Ordner, der Store hat die Seite noch nicht.
    private var haltBeforeStoringPage: Int?
    private var storedPages = 0
    #endif

    public init(
        store: PageStore, folder: URL, gate: SyncGate, deviceName: String,
        files: any SyncFileAccess = CoordinatedFileAccess()
    ) {
        self.store = store
        self.layout = SyncFolderLayout(chosenFolder: folder)
        self.gate = gate
        self.deviceName = deviceName
        self.files = files
    }

    /// Gleicht einmal ab. `connectedFolderID` ist die Ordner-ID, mit der der Sync
    /// eingerichtet wurde, `nil` beim ersten Verbinden; passt sie nicht zu `quill.json`,
    /// wirft es `SyncFailure.unknownFolder`, ohne etwas zu schreiben. Läuft schon ein
    /// Abgleich, beginnt dieser danach.
    public func sync(
        connectedFolderID: UUID?, progress: @escaping @Sendable (SyncProgress) -> Void = { _ in }
    ) async throws -> SyncReport {
        let previous = running
        let task = Task {
            _ = await previous?.result
            return try await self.run(connectedFolderID: connectedFolderID, progress: progress)
        }
        running = task
        return try await task.value
    }

    /// Merkt die Wahl des Nutzers bei einem Konflikt vor; der nächste Abgleich schreibt
    /// sie als eigene Änderung, in den Ordner und in den Store. Gibt es den Konflikt
    /// dann nicht mehr (z. B. auf einem anderen Gerät schon entschieden), entfällt sie.
    public func choose(_ choice: ConflictChoice) {
        choices[choice.documentID, default: []].append(choice)
    }

    private func run(connectedFolderID: UUID?, progress: @Sendable (SyncProgress) -> Void) async throws -> SyncReport {
        try gate.checkWritable()
        let folderID = try prepareFolder(connectedFolderID)
        let state = try await store.syncState()
        guard let deviceID = state.deviceID else { throw SyncFailure.notEnabled }
        device = deviceID
        cursors = SyncCursors(data: state.cursors)
        savedCursors = cursors
        report = SyncReport(folderID: folderID)
        assetNames = Set(try files.contents(of: layout.assets).filter(\.isDownloaded).map(\.name))
        try writeDeviceInfo()
        report.devices = deviceNames()

        var due = try await duePages()
        var done = 0
        progress(SyncProgress(done: 0, total: due.count))
        for page in due {
            try await syncPage(page)
            done += 1
            progress(SyncProgress(done: done, total: due.count))
        }
        // Neue Seiten anderer Geräte bekommen ihren Inhalt im selben Abgleich.
        due += try await syncTree()
        for page in due.dropFirst(done) {
            try await syncPage(page)
            done += 1
            progress(SyncProgress(done: done, total: due.count))
        }
        if cursors != savedCursors {
            try await store.saveSyncCursors(cursors.encoded())
        }
        return report
    }

    // MARK: Ordner

    private func prepareFolder(_ connected: UUID?) throws -> UUID {
        let manifestName = layout.manifest.lastPathComponent
        guard let entry = try files.contents(of: layout.root).first(where: { $0.name == manifestName }) else {
            if connected != nil { throw SyncFailure.folderMissing }
            try gate.checkWritable()
            let manifest = FolderManifest()
            try files.create(layout.manifest, with: manifest.encoded())
            return manifest.folderID
        }
        guard entry.isDownloaded else {
            try files.requestDownload(layout.manifest)
            throw SyncFailure.waitingForDownload
        }
        let manifest: FolderManifest
        do {
            manifest = try FolderManifest.decode(files.read(layout.manifest))
        } catch SyncError.newerFormat(let format) {
            throw SyncFailure.newerFormat(format)
        } catch {
            throw SyncFailure.unreadableManifest(String(describing: error))
        }
        guard manifest.folderID == connected else { throw SyncFailure.unknownFolder(manifest.folderID) }
        return manifest.folderID
    }

    /// `devices/<ID>.json`, neu bei geändertem Namen oder höchstens einmal am Tag.
    private func writeDeviceInfo() throws {
        let url = layout.device(device)
        let existing = try? DeviceInfo.decode(files.read(url))
        guard existing?.name != deviceName || existing.map({ Date.now.timeIntervalSince($0.lastSeen) > 24 * 3600 }) == true else {
            return
        }
        try gate.checkWritable()
        try files.replace(url, with: DeviceInfo(id: device, name: deviceName).encoded())
    }

    /// Namen aus `devices/`; nicht geladene oder unlesbare Dateien fehlen einfach.
    private func deviceNames() -> [UUID: String] {
        var names: [UUID: String] = [device: deviceName]
        for entry in (try? files.contents(of: layout.devices)) ?? [] where entry.isDownloaded && !entry.isDirectory {
            guard let id = UUID(uuidString: (entry.name as NSString).deletingPathExtension), id != device,
                  let info = try? DeviceInfo.decode(files.read(layout.device(id)))
            else { continue }
            names[id] = info.name
        }
        return names
    }

    /// Seiten, die seit dem letzten Abgleich lokal geändert wurden oder für die andere
    /// Geräte neue Dateien haben, und Seiten mit einer Wahl des Nutzers.
    private func duePages() async throws -> [UUID] {
        let dates = try await store.pageUpdateDates()
        updateDates = dates
        var due = Set(dates.filter { cursors.synced[$0.key.uuidString] != $0.value }.map(\.key))
        due.formUnion(choices.keys.filter { dates[$0] != nil })
        for folder in try files.contents(of: layout.pages) where folder.isDirectory {
            guard let page = UUID(uuidString: folder.name), dates[page] != nil, !due.contains(page) else { continue }
            if try hasNewFiles(in: layout.pages.appending(path: folder.name, directoryHint: .isDirectory), document: folder.name) {
                due.insert(page)
            }
        }
        return due.sorted { $0.uuidString < $1.uuidString }
    }

    private func hasNewFiles(in folder: URL, document: String) throws -> Bool {
        for deviceFolder in try files.contents(of: folder) where deviceFolder.isDirectory {
            guard let other = UUID(uuidString: deviceFolder.name), other != device else { continue }
            let last = cursors.last(document, device: other)
            let numbers = try files.contents(of: folder.appending(path: deviceFolder.name, directoryHint: .isDirectory))
                .compactMap { SyncFolderLayout.changesNumber($0.name) }
            if numbers.contains(where: { $0 > last }) { return true }
        }
        return false
    }

    // MARK: Seiten

    private func syncPage(_ pageID: UUID) async throws {
        guard let state = try await store.syncPage(pageID) else { return }
        let key = pageID.uuidString
        let document: PageDocument
        do {
            document = try state.document.map { try PageDocument(bytes: $0) } ?? PageDocument()
        } catch {
            report.unreadable.append(UnreadableFile(path: "Store: \(key)", reason: String(describing: error)))
            return
        }
        document.write(as: device)
        let loaded = document.version
        var next = cursors
        let pageFolder = layout.pages.appending(path: key, directoryHint: .isDirectory)
        let ownFolder = layout.page(pageID, device: device)
        var ownLast = try importFiles(in: ownFolder, into: document, key: key, from: device, cursors: &next)

        // Lokale Änderungen
        let beforeExport = document.version
        var assetFiles = try document.assetFiles()
        for block in state.blocks {
            guard let asset = block.properties.assetID, assetFiles[asset] == nil,
                  let image = try await store.imageData(asset)
            else { continue }
            assetFiles[asset] = try writeAsset(image.data, uti: image.uti)
        }
        let changed = try document.update(to: state.blocks, assetFiles: assetFiles)
        try appendLocal(document, changed: changed, since: beforeExport, key: key, in: ownFolder, last: &ownLast, cursors: &next)
        next.setLast(ownLast, key, device: device)

        // Änderungen anderer Geräte
        let beforeImport = document.version
        let before = try document.blocks()
        for other in try otherDevices(in: pageFolder) {
            _ = try importFiles(in: layout.page(pageID, device: other), into: document, key: key, from: other, cursors: &next)
        }
        let imported = document.version
        let restored = try document.restoreDeletedWhileEdited(since: beforeImport)
        if !restored.isEmpty {
            report.restoredBlocks += restored
            try append(document.changes(since: imported), in: ownFolder, last: &ownLast)
            next.setLast(ownLast, key, device: device)
        }
        if try applyChoices(pageID, to: document, in: ownFolder, last: &ownLast) {
            next.setLast(ownLast, key, device: device)
        }
        let after = try document.blocks()
        guard try await fetchAssets(of: after, files: document.assetFiles()) else { return }
        let conflicts = try document.conflicts()
        if !conflicts.isEmpty { report.conflicts[pageID] = conflicts }

        let edits = Self.edits(from: before, to: after)
        guard document.version != loaded || next != cursors || !edits.isEmpty else {
            if let date = updateDates[pageID] { cursors.synced[key] = date }
            return
        }
        #if DEBUG || QUILL_SYNCTEST
        await haltIfRequested()
        #endif
        guard let updated = try await store.applySyncPage(
            pageID, expected: state.blocks, edits: edits, document: document.save(), cursors: next.encoded()
        ) else {
            report.postponed.append(pageID)
            return
        }
        cursors = next
        savedCursors = next
        cursors.synced[key] = updated
        if !edits.isEmpty { report.changedPages.insert(pageID) }
    }

    #if DEBUG || QUILL_SYNCTEST
    public func setHaltBeforeStoringPage(_ number: Int?) {
        haltBeforeStoringPage = number
    }

    private func haltIfRequested() async {
        storedPages += 1
        guard storedPages == haltBeforeStoringPage else { return }
        while true { try? await Task.sleep(for: .seconds(60)) }
    }
    #endif

    /// Holt Bilder aus dem Ordner, die der Store noch nicht hat. `false`, wenn eines
    /// fehlt oder noch nicht geladen ist: Dann wartet die Seite, sonst verlöre der Block
    /// beim Speichern seinen Verweis aufs Bild.
    private func fetchAssets(of blocks: [BlockSnapshot], files assetFiles: [UUID: String]) async throws -> Bool {
        for block in blocks {
            guard let asset = block.properties.assetID, try await !store.hasAsset(asset) else { continue }
            guard let name = assetFiles[asset] else {
                report.waitingForDownload.append("assets/?\(asset.uuidString)")
                return false
            }
            let url = layout.assets.appending(path: name)
            guard assetNames.contains(name) else {
                try? files.requestDownload(url)
                report.waitingForDownload.append("assets/\(name)")
                return false
            }
            let data = try files.read(url)
            let fileExtension = (name as NSString).pathExtension
            try await store.insertSyncedAsset(
                id: asset, data: data, uti: UTType(filenameExtension: fileExtension)?.identifier ?? UTType.png.identifier
            )
        }
        return true
    }

    private func writeAsset(_ data: Data, uti: String) throws -> String {
        let url = layout.asset(data, fileExtension: UTType(uti)?.preferredFilenameExtension ?? "png")
        let name = url.lastPathComponent
        if !assetNames.contains(name) {
            try gate.checkWritable()
            do {
                try files.create(url, with: data)
            } catch CocoaError.fileWriteFileExists {
                // Gleicher Inhalt von einem anderen Gerät, gleichzeitig angelegt.
            }
            assetNames.insert(name)
        }
        return name
    }

    /// Diff der Blöcke für `PageStore.applyEdits`. Die Reihenfolge geht nur mit, wenn
    /// sie sich geändert hat oder Blöcke dazukamen.
    static func edits(from before: [BlockSnapshot], to after: [BlockSnapshot]) -> BlockEdits {
        let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remaining = Set(after.map(\.id))
        let upserts = after.filter { old[$0.id] != $0 }
        let deletions = before.map(\.id).filter { !remaining.contains($0) }
        let keptOrder = before.map(\.id).filter(remaining.contains)
        let order = after.map(\.id) == keptOrder ? nil : after.map(\.id)
        return BlockEdits(upserts: upserts, deletions: deletions, order: order)
    }

    // MARK: Seitenbaum

    /// Gibt die Seiten zurück, die dabei neu in den Store kamen.
    private func syncTree() async throws -> [UUID] {
        let state = try await store.syncState()
        let key = SyncCursors.treeKey
        let document: TreeDocument
        do {
            document = try state.tree.map { try TreeDocument(bytes: $0) } ?? TreeDocument()
        } catch {
            report.unreadable.append(UnreadableFile(path: "Store: \(key)", reason: String(describing: error)))
            return []
        }
        document.write(as: device)
        let loaded = document.version
        var next = cursors
        let ownFolder = layout.tree(device: device)
        var ownLast = try importFiles(in: ownFolder, into: document, key: key, from: device, cursors: &next)

        // Lokale Änderungen, auch endgültig gelöschte Seiten (Grabstein)
        let beforeExport = document.version
        let pages = try await store.pageSnapshots()
        let inStore = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Dictionary(try document.records().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var records: [PageRecord] = []
        for page in pages {
            var record = PageRecord(page)
            let existing = known[page.id]
            if page.trashedAt != nil {
                record.trashedVersion = existing?.trashedAt == page.trashedAt
                    ? existing?.trashedVersion : try await pageDocument(page.id).version
            }
            records.append(record)
        }
        var changed = try document.update(records)
        for record in known.values where record.deletedAt == nil && inStore[record.id] == nil {
            let version = record.trashedAt == nil ? folderPageVersion(record.id) : nil
            changed = try document.markDeleted(record.id, trashedVersion: version) || changed
        }
        try appendLocal(document, changed: changed, since: beforeExport, key: key, in: ownFolder, last: &ownLast, cursors: &next)
        next.setLast(ownLast, key, device: device)

        // Änderungen anderer Geräte
        let before = Dictionary(try document.records().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for other in try otherDevices(in: layout.tree) {
            _ = try importFiles(in: layout.tree(device: other), into: document, key: key, from: other, cursors: &next)
        }
        let imported = document.version
        try await keepEditedPages(document, before: before, inStore: inStore, ownFolder: ownFolder, imported: imported, ownLast: &ownLast)
        _ = try applyChoices(SyncReport.treeID, to: document, in: ownFolder, last: &ownLast)
        next.setLast(ownLast, key, device: device)

        var changes: [PageSnapshotChange] = []
        var created: [UUID] = []
        for record in try document.records() where before[record.id] != record {
            let current = inStore[record.id]
            // Hier schon endgültig gelöscht: bleibt weg.
            guard current != nil || (record.deletedAt == nil && before[record.id] == nil) else { continue }
            changes.append(PageSnapshotChange(expected: current, new: record.snapshot))
            if current == nil { created.append(record.id) }
        }
        let conflicts = try document.conflicts()
        if !conflicts.isEmpty { report.conflicts[SyncReport.treeID] = conflicts }
        guard document.version != loaded || next != cursors || !changes.isEmpty else { return [] }
        guard try await store.applySyncTree(changes, tree: document.save(), cursors: next.encoded()) else {
            report.postponed.append(SyncReport.treeID)
            return []
        }
        cursors = next
        savedCursors = next
        report.changedPages.formUnion(changes.map(\.new.id))
        return created
    }

    /// Schreibt die vorgemerkte Wahl des Nutzers ins Dokument und als nächste eigene
    /// Datei, nach den Änderungen der anderen Geräte: So entscheidet der Nutzer über
    /// das, was er gesehen hat, und eine inzwischen anderswo getroffene Wahl bleibt.
    /// `true`, wenn eine Datei dazukam.
    private func applyChoices(_ documentID: UUID, to document: SyncDocument, in folder: URL, last: inout Int) throws -> Bool {
        guard let chosen = choices.removeValue(forKey: documentID) else { return false }
        let before = document.version
        var resolved = false
        for choice in chosen {
            resolved = try document.resolve(choice.objectID, field: choice.field, choosing: choice.value) || resolved
        }
        guard resolved else { return false }
        try append(document.changes(since: before), in: folder, last: &last)
        return true
    }

    /// Papierkorb gegen Bearbeiten (ADR-029): Kommt eine Seite von einem anderen Gerät
    /// in den Papierkorb (oder wurde dort endgültig gelöscht), die dieses Gerät seitdem
    /// bearbeitet hat, bleibt sie hier und ist als wiederhergestellt markiert.
    private func keepEditedPages(
        _ document: TreeDocument, before: [UUID: PageRecord], inStore: [UUID: PageSnapshot],
        ownFolder: URL, imported: DocumentVersion, ownLast: inout Int
    ) async throws {
        var kept: [PageRecord] = []
        for record in try document.records() where record.trashedAt != nil || record.deletedAt != nil {
            guard let previous = before[record.id], previous.trashedAt == nil, previous.deletedAt == nil,
                  inStore[record.id] != nil, try await editedSinceTrash(record)
            else { continue }
            var keep = record
            keep.trashedAt = nil
            keep.isRestored = true
            kept.append(keep)
        }
        guard !kept.isEmpty, try document.update(kept) else { return }
        report.restoredPages += kept.map(\.id)
        try append(document.changes(since: imported), in: ownFolder, last: &ownLast)
    }

    /// Hat dieses Gerät die Seite geändert, seit sie auf dem anderen Gerät in den
    /// Papierkorb kam? Kennt das Seiten-Dokument den Stand von damals nicht, gilt sie
    /// als geändert: lieber eine Seite zu viel behalten als eine verlieren.
    private func editedSinceTrash(_ record: PageRecord) async throws -> Bool {
        let page = try await pageDocument(record.id)
        guard let version = record.trashedVersion, page.contains(version) else { return true }
        return try page.blocks(at: version) != page.blocks()
    }

    /// Stand des Seiten-Dokuments einer hier schon gelöschten Seite: aus den Dateien im
    /// Ordner bis zu den gelesenen Nummern, also genau das, was dieses Gerät kannte.
    /// `nil`, wenn eine Datei fehlt oder unlesbar ist.
    private func folderPageVersion(_ pageID: UUID) -> DocumentVersion? {
        let key = pageID.uuidString
        let document = PageDocument()
        let pageFolder = layout.pages.appending(path: key, directoryHint: .isDirectory)
        guard let devices = try? files.contents(of: pageFolder).filter(\.isDirectory).compactMap({ UUID(uuidString: $0.name) }) else {
            return nil
        }
        for source in devices {
            let last = cursors.last(key, device: source)
            guard last > 0 else { continue }
            for number in 1...last {
                guard let data = try? files.read(SyncFolderLayout.changes(number, in: layout.page(pageID, device: source))),
                      (try? document.apply(changes: data)) != nil
                else { return nil }
            }
        }
        return document.version
    }

    private func pageDocument(_ pageID: UUID) async throws -> PageDocument {
        guard let data = try await store.syncPage(pageID)?.document else { return PageDocument() }
        return try PageDocument(bytes: data)
    }

    // MARK: Dateien

    private func otherDevices(in folder: URL) throws -> [UUID] {
        try files.contents(of: folder).filter(\.isDirectory).compactMap { UUID(uuidString: $0.name) }
            .filter { $0 != device }.sorted { $0.uuidString < $1.uuidString }
    }

    /// Übernimmt neue Dateien eines Geräts der Reihe nach, bis zur ersten Lücke, zur
    /// ersten nicht geladenen oder unlesbaren Datei. Gibt die höchste vorhandene Nummer
    /// zurück (für eigene Ordner: die nächste Datei bekommt die Nummer danach).
    private func importFiles(
        in folder: URL, into document: SyncDocument, key: String, from source: UUID, cursors next: inout SyncCursors
    ) throws -> Int {
        var entries: [Int: SyncFileEntry] = [:]
        for entry in try files.contents(of: folder) where !entry.isDirectory {
            if let number = SyncFolderLayout.changesNumber(entry.name) { entries[number] = entry }
        }
        var last = next.last(key, device: source)
        while let entry = entries[last + 1] {
            let url = SyncFolderLayout.changes(last + 1, in: folder)
            guard entry.isDownloaded else {
                try? files.requestDownload(url)
                report.waitingForDownload.append(relativePath(url))
                break
            }
            do {
                try document.apply(changes: files.read(url))
            } catch {
                report.unreadable.append(UnreadableFile(path: relativePath(url), reason: String(describing: error)))
                break
            }
            last += 1
        }
        next.setLast(last, key, device: source)
        return max(last, entries.keys.max() ?? 0)
    }

    /// Hängt `changes` als nächste eigene Datei an.
    /// Lokale Änderungen als nächste eigene Datei. Steht das Dokument noch nicht in
    /// diesem Ordner, ist es der ganze Stand samt Geschichte, auch was andere Geräte im
    /// vorherigen Ordner beigetragen haben: Ein Gerät hier soll auch ältere Stände
    /// abrufen können. Die Datei heißt trotzdem `<Nr>.changes`, weil der Lesepfad beides
    /// annimmt; beim Verdichten vor v0.4.0 wird daraus `snapshot` (ADR-029).
    private func appendLocal(
        _ document: SyncDocument, changed: Bool, since version: DocumentVersion, key: String,
        in folder: URL, last: inout Int, cursors next: inout SyncCursors
    ) throws {
        if next.inFolder.contains(key) {
            if changed { try append(document.changes(since: version), in: folder, last: &last) }
            return
        }
        if !document.isEmpty { try append(document.save(), in: folder, last: &last) }
        next.inFolder.insert(key)
    }

    private func append(_ changes: Data, in folder: URL, last: inout Int) throws {
        guard !changes.isEmpty else { return }
        try gate.checkWritable()
        try files.create(SyncFolderLayout.changes(last + 1, in: folder), with: changes)
        last += 1
    }

    private func relativePath(_ url: URL) -> String {
        String(url.path(percentEncoded: false).dropFirst(layout.root.path(percentEncoded: false).count))
    }
}
