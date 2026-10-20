import Foundation
import SwiftData

/// Seite als `Sendable`-Werttyp für die Sync-Schicht (ADR-029), wie `BlockSnapshot`
/// für Blöcke. Ohne Blöcke, Workspace und `updatedAt`.
public struct PageSnapshot: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var icon: String?
    public var parentID: UUID?
    public var sortKey: String
    public var isFavorite: Bool
    public var favoriteSortKey: String?
    public var trashedAt: Date?
    /// Rohwert von `PageKind`; unbekannte Werte späterer Versionen bleiben erhalten.
    public var kindRaw: String
    public var createdAt: Date
    public var isRestored: Bool

    public init(
        id: UUID, title: String = "", icon: String? = nil, parentID: UUID? = nil, sortKey: String = "",
        isFavorite: Bool = false, favoriteSortKey: String? = nil, trashedAt: Date? = nil,
        kindRaw: String = PageKind.page.rawValue, createdAt: Date = .now, isRestored: Bool = false
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.parentID = parentID
        self.sortKey = sortKey
        self.isFavorite = isFavorite
        self.favoriteSortKey = favoriteSortKey
        self.trashedAt = trashedAt
        self.kindRaw = kindRaw
        self.createdAt = createdAt
        self.isRestored = isRestored
    }
}

/// Stand des Sync im Store (Schema V2): Geräte-ID, Seitenbaum, gelesene Dateien.
public struct SyncStoreState: Equatable, Sendable {
    public var deviceID: UUID?
    public var tree: Data?
    public var cursors: Data?

    public init(deviceID: UUID?, tree: Data?, cursors: Data?) {
        self.deviceID = deviceID
        self.tree = tree
        self.cursors = cursors
    }
}

/// Blöcke und Sync-Dokument einer Seite.
public struct SyncPageState: Equatable, Sendable {
    public var blocks: [BlockSnapshot]
    public var document: Data?
}

/// Eine Seite, wie die Sync-Schicht sie in den Store schreiben will. `expected` ist der
/// Stand, von dem sie ausging (`nil` = Seite neu); weicht der Store davon ab, hat der
/// Nutzer inzwischen geändert, und nichts wird geschrieben.
public struct PageSnapshotChange: Equatable, Sendable {
    public var expected: PageSnapshot?
    public var new: PageSnapshot

    public init(expected: PageSnapshot?, new: PageSnapshot) {
        self.expected = expected
        self.new = new
    }
}

/// Schreibwege der Sync-Schicht (ADR-029). Eingehende Änderungen werden nur
/// übernommen, wenn der Store noch dem Stand entspricht, von dem der Abgleich ausging;
/// sonst schreibt die Methode nichts und gibt `false` zurück, und der nächste Abgleich
/// nimmt die neue Änderung des Nutzers mit. So überschreibt der Abgleich nie eine
/// Eingabe, die während des Abgleichs gespeichert wurde.
extension PageStore {
    public func syncState() throws -> SyncStoreState {
        let workspace = try primaryWorkspace()
        try save()
        return SyncStoreState(deviceID: workspace.syncDeviceID, tree: workspace.syncTree, cursors: workspace.syncCursors)
    }

    /// Neue Geräte-ID; `nil` löscht sie. Gelesene Dateien und Seitenbaum bleiben:
    /// Auch als neues Gerät kennt der Store, was er schon übernommen hat.
    public func setSyncDeviceID(_ id: UUID?) throws {
        let workspace = try primaryWorkspace()
        workspace.syncDeviceID = id
        try save()
    }

    /// Vergisst die gelesenen Dateien, nicht die Sync-Dokumente samt Geschichte. Vor dem
    /// Verbinden mit einem anderen Ordner: Die Nummern gehören zum bisherigen Ordner,
    /// und der erste Abgleich schreibt jedes Dokument als ganzen Stand in den neuen.
    public func resetSyncCursors() throws {
        try primaryWorkspace().syncCursors = nil
        try save()
    }

    /// Alle Seiten, auch im Papierkorb.
    public func pageSnapshots() throws -> [PageSnapshot] {
        try modelContext.fetch(FetchDescriptor<Page>()).map(\.snapshot).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// `updatedAt` aller Seiten: Was sich seit dem letzten Abgleich geändert hat, ist fällig.
    public func pageUpdateDates() throws -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for page in try modelContext.fetch(FetchDescriptor<Page>()) { result[page.id] = page.updatedAt }
        return result
    }

    /// Speichert nur die gelesenen Dateien.
    public func saveSyncCursors(_ cursors: Data) throws {
        let workspace = try primaryWorkspace()
        workspace.syncCursors = cursors
        try save()
    }

    /// `nil`, wenn es die Seite (nicht mehr) gibt.
    public func syncPage(_ pageID: UUID) throws -> SyncPageState? {
        guard let page = try? fetchPage(pageID, prefetching: [\.blocks]) else { return nil }
        return SyncPageState(blocks: orderedBlocks(of: page).map(\.snapshot), document: page.syncDocument)
    }

    /// Übernimmt Seiten aus dem Seitenbaum, speichert Seitenbaum und gelesene Dateien
    /// in einem Schritt. Seiten werden hier nie gelöscht, nur angelegt, geändert oder in
    /// den Papierkorb gelegt (ADR-029). `false`, wenn der Store vom erwarteten Stand
    /// abweicht; dann ist nichts geschrieben.
    public func applySyncTree(_ changes: [PageSnapshotChange], tree: Data, cursors: Data) throws -> Bool {
        let workspace = try primaryWorkspace()
        var pages: [UUID: Page] = [:]
        for page in try modelContext.fetch(FetchDescriptor<Page>()) where pages[page.id] == nil {
            pages[page.id] = page
        }
        for change in changes where pages[change.new.id]?.snapshot != change.expected {
            modelContext.rollback()
            return false
        }
        var touched: [Page] = []
        for change in changes {
            let page: Page
            if let existing = pages[change.new.id] {
                page = existing
            } else {
                page = Page()
                page.id = change.new.id
                modelContext.insert(page)
                page.workspace = workspace
                pages[page.id] = page
            }
            page.apply(change.new)
            touched.append(page)
        }
        // Eltern erst, wenn alle Seiten da sind; fehlt die Elternseite, oberste Ebene.
        for (page, change) in zip(touched, changes) {
            let parent = change.new.parentID.flatMap { pages[$0] }
            if page.parent?.id != parent?.id { page.parent = parent }
        }
        Self.breakCycles(in: touched)
        workspace.syncTree = tree
        workspace.syncCursors = cursors
        try save()
        return true
    }

    /// Übernimmt Blöcke einer Seite und speichert ihr Sync-Dokument und die gelesenen
    /// Dateien in einem Schritt. `expected` sind die Blöcke, von denen der Abgleich
    /// ausging; weicht die Seite davon ab, wird nichts geschrieben (`nil`). Sonst
    /// `updatedAt` der Seite danach.
    public func applySyncPage(
        _ pageID: UUID, expected: [BlockSnapshot], edits: BlockEdits, document: Data, cursors: Data
    ) throws -> Date? {
        let workspace = try primaryWorkspace()
        guard let page = try? fetchPage(pageID, prefetching: [\.blocks]),
              orderedBlocks(of: page).map(\.snapshot) == expected
        else {
            modelContext.rollback()
            return nil
        }
        _ = apply(edits, to: page)
        page.syncDocument = document
        workspace.syncCursors = cursors
        try save()
        return page.updatedAt
    }

    /// Markiert eine Seite als vom Sync wiederhergestellt oder nimmt die Marke weg.
    public func setRestored(_ pageID: UUID, _ isRestored: Bool) throws {
        let page = try fetchPage(pageID)
        guard page.isRestored != isRestored else { return }
        page.isRestored = isRestored
        try save()
    }

    public func hasAsset(_ id: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetchCount(descriptor) > 0
    }

    /// Legt ein Bild aus dem Sync-Ordner unverändert an (nicht neu kodiert: der Name im
    /// Ordner hängt am Inhalt). Gibt es das Asset schon, passiert nichts.
    public func insertSyncedAsset(id: UUID, data: Data, uti: String) throws {
        guard try !hasAsset(id) else { return }
        let asset = Asset(data: data, uti: uti)
        asset.id = id
        if let size = ImageImport.pixelSize(of: data) {
            asset.pixelWidth = size.width
            asset.pixelHeight = size.height
        }
        modelContext.insert(asset)
        try save()
    }

    /// Seiten, die über ihre Eltern im Kreis hängen (zwei Geräte haben gleichzeitig
    /// über Kreuz verschoben), kommen auf die oberste Ebene: je Kreis die Seite mit der
    /// kleinsten ID, auf jedem Gerät dieselbe.
    static func breakCycles(in pages: [Page]) {
        for page in pages {
            var path: [Page] = []
            var current: Page? = page
            while let candidate = current {
                if let start = path.firstIndex(where: { $0 === candidate }) {
                    let cycle = path[start...]
                    cycle.min { $0.id.uuidString < $1.id.uuidString }?.parent = nil
                    break
                }
                path.append(candidate)
                current = candidate.parent
            }
        }
    }
}

extension Page {
    var snapshot: PageSnapshot {
        PageSnapshot(
            id: id, title: title, icon: icon, parentID: parent?.id, sortKey: sortKey, isFavorite: isFavorite,
            favoriteSortKey: favoriteSortKey, trashedAt: trashedAt, kindRaw: kindRaw, createdAt: createdAt, isRestored: isRestored
        )
    }

    /// Übernimmt alle Felder außer den Eltern (die setzt `applySyncTree` danach).
    fileprivate func apply(_ snapshot: PageSnapshot) {
        let before = self.snapshot
        title = snapshot.title
        icon = snapshot.icon
        sortKey = snapshot.sortKey
        isFavorite = snapshot.isFavorite
        favoriteSortKey = snapshot.favoriteSortKey
        trashedAt = snapshot.trashedAt
        kindRaw = snapshot.kindRaw
        createdAt = snapshot.createdAt
        isRestored = snapshot.isRestored
        if self.snapshot != before { updatedAt = .now }
    }
}
