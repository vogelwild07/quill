import Foundation
import SwiftData

/// Stelle unter Geschwistern, an die eine Seite kommt.
public enum SiblingPosition: Sendable, Hashable {
    case first
    case last
    case before(UUID)
    case after(UUID)
}

/// Ort einer Seite im Baum, z. B. um Verschieben rückgängig zu machen.
public struct PageLocation: Sendable, Hashable {
    public let parentID: UUID?
    public let position: SiblingPosition
}

public enum PageStoreError: Error, Equatable {
    case pageNotFound(UUID)
    /// Die Bezugsseite der Position ist kein Geschwister unter dem Ziel.
    case siblingNotFound(UUID)
    /// Eine Seite kann nicht unter sich selbst oder eine eigene Unterseite.
    case cycle
    /// Endgültig löschen geht nur aus dem Papierkorb.
    case notInTrash(UUID)
}

/// Alle Schreibzugriffe auf Seiten. Die UI liest per `@Query`.
///
/// Schnittstelle nur mit `UUID`s, damit nichts Nicht-`Sendable` den Actor verlässt.
/// Jede Methode speichert sofort.
@ModelActor
public actor PageStore {
    /// Stellt sicher, dass es genau einen Workspace gibt (ADR-003), und gibt seine ID zurück.
    ///
    /// Doppelte Workspaces (z. B. später durch Sync) werden in den ältesten
    /// zusammengeführt; Seiten ohne Workspace werden ihm zugeordnet.
    @discardableResult
    public func ensureWorkspace() throws -> UUID {
        let workspace = try primaryWorkspace()
        try save()
        return workspace.id
    }

    @discardableResult
    public func createPage(
        title: String = "",
        in parentID: UUID? = nil,
        at position: SiblingPosition = .last
    ) throws -> UUID {
        let workspace = try primaryWorkspace()
        let parent = try parentID.map(fetchPage)
        let page = Page(title: title)
        modelContext.insert(page)
        page.workspace = workspace
        page.sortKey = try sortKey(at: position, among: try siblings(of: parent, excluding: page))
        page.parent = parent
        try save()
        return page.id
    }

    public func rename(_ pageID: UUID, to title: String) throws {
        let page = try fetchPage(pageID)
        guard page.title != title else { return }
        page.title = title
        page.updatedAt = .now
        try save()
    }

    /// `icon` ist ein Emoji oder `nil` zum Entfernen.
    public func setIcon(_ pageID: UUID, to icon: String?) throws {
        let page = try fetchPage(pageID)
        guard page.icon != icon else { return }
        page.icon = icon
        page.updatedAt = .now
        try save()
    }

    /// Verschiebt eine Seite unter `parentID` (`nil` = oberste Ebene).
    ///
    /// Ändert im Normalfall nur diese eine Seite.
    public func move(_ pageID: UUID, to parentID: UUID?, at position: SiblingPosition) throws {
        let page = try fetchPage(pageID)
        let parent = try parentID.map(fetchPage)
        var ancestor = parent
        while let current = ancestor {
            if current.id == pageID { throw PageStoreError.cycle }
            ancestor = current.parent
        }
        page.sortKey = try sortKey(at: position, among: try siblings(of: parent, excluding: page))
        page.parent = parent
        page.updatedAt = .now
        try save()
    }

    /// Aktueller Ort: Elternseite und Stelle relativ zum vorherigen Geschwister
    /// (inklusive Papierkorb). `move(id, to: parentID, at: position)` stellt ihn wieder her.
    public func location(of pageID: UUID) throws -> PageLocation {
        let page = try fetchPage(pageID)
        let siblings = try siblings(of: page.parent, excluding: page)
        let previous = siblings.last { ($0.sortKey, $0.createdAt, $0.id.uuidString) < (page.sortKey, page.createdAt, page.id.uuidString) }
        return PageLocation(parentID: page.parent?.id, position: previous.map { .after($0.id) } ?? .first)
    }

    /// Legt die Seite in den Papierkorb. Unterseiten folgen logisch, ohne eigenes Datum.
    public func trash(_ pageID: UUID) throws {
        let page = try fetchPage(pageID)
        guard page.trashedAt == nil else { return }
        page.trashedAt = .now
        page.updatedAt = .now
        try save()
    }

    /// Holt die Seite aus dem Papierkorb. Liegt eine Elternseite noch darin,
    /// kommt sie ans Ende der obersten Ebene, damit sie sichtbar wird.
    public func restore(_ pageID: UUID) throws {
        let page = try fetchPage(pageID)
        guard page.trashedAt != nil else { return }
        page.trashedAt = nil
        page.updatedAt = .now
        if page.parent.map(isInTrash) == true {
            page.sortKey = try sortKey(at: .last, among: try siblings(of: nil, excluding: page))
            page.parent = nil
        }
        try save()
    }

    // MARK: - Hilfen

    func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    func fetchPage(_ id: UUID) throws -> Page {
        var descriptor = FetchDescriptor<Page>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let page = try modelContext.fetch(descriptor).first else {
            throw PageStoreError.pageNotFound(id)
        }
        return page
    }

    private func primaryWorkspace() throws -> Workspace {
        let workspaces = try modelContext.fetch(FetchDescriptor<Workspace>())
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        guard let primary = workspaces.first else {
            let workspace = Workspace()
            modelContext.insert(workspace)
            return workspace
        }
        for duplicate in workspaces.dropFirst() {
            for page in duplicate.pages ?? [] {
                page.workspace = primary
            }
            modelContext.delete(duplicate)
        }
        let orphans = try modelContext.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.workspace == nil }))
        for page in orphans {
            page.workspace = primary
        }
        return primary
    }

    /// Liegt die Seite selbst oder eine ihrer Elternseiten im Papierkorb?
    func isInTrash(_ page: Page) -> Bool {
        var current: Page? = page
        while let candidate = current {
            if candidate.trashedAt != nil { return true }
            current = candidate.parent
        }
        return false
    }

    /// Geschwister in Anzeigereihenfolge, inklusive Papierkorb, damit
    /// Wiederherstellen den alten Platz behält.
    private func siblings(of parent: Page?, excluding page: Page) throws -> [Page] {
        let candidates: [Page]
        if let parent {
            candidates = parent.children ?? []
        } else {
            candidates = try modelContext.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.parent == nil }))
        }
        return candidates
            .filter { $0.id != page.id }
            .sorted { ($0.sortKey, $0.createdAt, $0.id.uuidString) < ($1.sortKey, $1.createdAt, $1.id.uuidString) }
    }

    /// Neuer Schlüssel für `position`. Sind die Schlüssel der Geschwister doppelt
    /// oder ungültig, werden sie einmal neu vergeben (seltene Reparatur).
    private func sortKey(at position: SiblingPosition, among siblings: [Page]) throws -> String {
        try fractionalKey(at: position, among: siblings, key: \.sortKey) { $0.sortKey = $1 }
    }

    /// Schlüssel für `position` in einer nach `key` sortierten Liste (ADR-009), für
    /// `sortKey` und `favoriteSortKey`.
    func fractionalKey(
        at position: SiblingPosition, among siblings: [Page],
        key: (Page) -> String?, repair: (Page, String) -> Void
    ) throws -> String {
        let index: Int
        switch position {
        case .first:
            index = 0
        case .last:
            index = siblings.count
        case .before(let id):
            guard let found = siblings.firstIndex(where: { $0.id == id }) else {
                throw PageStoreError.siblingNotFound(id)
            }
            index = found
        case .after(let id):
            guard let found = siblings.firstIndex(where: { $0.id == id }) else {
                throw PageStoreError.siblingNotFound(id)
            }
            index = found + 1
        }

        let lower = index > 0 ? key(siblings[index - 1]) ?? "" : nil
        let upper = index < siblings.count ? key(siblings[index]) ?? "" : nil
        if let key = try? FractionalIndex.key(between: lower, and: upper),
           lower.map(FractionalIndex.isValid) ?? true,
           upper.map(FractionalIndex.isValid) ?? true {
            return key
        }

        let keys = FractionalIndex.keys(count: siblings.count + 1)
        for (sibling, newKey) in zip(siblings, keys.enumerated().filter { $0.offset != index }.map(\.element)) {
            repair(sibling, newKey)
            sibling.updatedAt = .now
        }
        return keys[index]
    }
}

// MARK: - Blöcke

extension PageStore {
    /// Blöcke einer Seite in Anzeigereihenfolge.
    public func blocks(of pageID: UUID) throws -> [BlockSnapshot] {
        try orderedBlocks(of: fetchPage(pageID)).map(\.snapshot)
    }

    /// Übernimmt Änderungen an Blöcken in einem Speichervorgang.
    ///
    /// `updatedAt` ändert sich nur bei Blöcken, deren Inhalt sich wirklich ändert.
    /// Für die Reihenfolge bekommen nur Blöcke einen neuen `sortKey`, die nicht schon
    /// richtig stehen (längste aufsteigende Teilfolge), wie bei Seiten (ADR-009).
    public func applyEdits(_ pageID: UUID, _ edits: BlockEdits) throws {
        guard !edits.isEmpty else { return }
        let page = try fetchPage(pageID)
        var byID: [UUID: Block] = [:]
        for block in page.blocks ?? [] where byID[block.id] == nil {
            byID[block.id] = block
        }
        var changed = false

        for id in edits.deletions {
            guard let block = byID.removeValue(forKey: id) else { continue }
            // Asset lösen, sonst löscht die Regel `cascade` es mit, und Undo hätte
            // kein Bild mehr. Es bleibt verwaist liegen (ADR-015).
            if let asset = block.asset {
                block.asset = nil
                asset.updatedAt = .now
            }
            modelContext.delete(block)
            changed = true
        }

        var inserted: [Block] = []
        for snapshot in edits.upserts {
            let block: Block
            if let existing = byID[snapshot.id] {
                block = existing
            } else {
                block = Block()
                block.id = snapshot.id
                modelContext.insert(block)
                block.page = page
                byID[snapshot.id] = block
                inserted.append(block)
            }
            if block.apply(snapshot) {
                block.updatedAt = .now
                changed = true
            }
        }

        if let order = edits.order {
            let ordered = order.compactMap { byID[$0] }
            let orderedIDs = Set(ordered.map(\.id))
            let others = byID.values.filter { !orderedIDs.contains($0.id) }
            changed = assignSortKeys(order: ordered, others: others) || changed
        }
        // Neue Blöcke ohne Reihenfolge kommen ans Ende.
        let unplaced = inserted.filter { !FractionalIndex.isValid($0.sortKey) }
        if !unplaced.isEmpty {
            let last = byID.values.map(\.sortKey).filter(FractionalIndex.isValid).max()
            // `last` ist gültig und die Lücke nach oben offen: wirft nicht (Test
            // `blocksAreAppendedAfterHighestKeys`). Der Ausweichpfad ist nur Absicherung.
            let keys = (try? FractionalIndex.keys(count: unplaced.count, between: last, and: nil))
                ?? FractionalIndex.keys(count: unplaced.count)
            for (block, key) in zip(unplaced, keys) { block.sortKey = key }
            changed = true
        }

        if changed {
            page.updatedAt = .now
            try save()
        }
    }

    // MARK: - Hilfen

    private func orderedBlocks(of page: Page) -> [Block] {
        (page.blocks ?? []).sorted { ($0.sortKey, $0.createdAt, $0.id.uuidString) < ($1.sortKey, $1.createdAt, $1.id.uuidString) }
    }

    /// Vergibt Schlüssel so, dass `order` aufsteigend ist, und ändert dabei möglichst
    /// wenige Blöcke. `others` sind Blöcke der Seite, die in `order` fehlen (z. B. aus
    /// einem anderen Fenster); ihre Schlüssel werden nie doppelt vergeben.
    /// Gibt zurück, ob sich ein Schlüssel geändert hat.
    private func assignSortKeys(order: [Block], others: [Block]) -> Bool {
        let keep = Self.longestIncreasingRun(order.map(\.sortKey))
        let foreignKeys = others.map(\.sortKey).filter(FractionalIndex.isValid).sorted()
        var changed = false
        var index = 0
        while index < order.count {
            guard !keep.contains(index) else {
                index += 1
                continue
            }
            var end = index
            while end < order.count && !keep.contains(end) { end += 1 }
            var lower = index > 0 ? order[index - 1].sortKey : nil
            let upper = end < order.count ? order[end].sortKey : nil
            // Liegt ein fremder Schlüssel in der Lücke, beginnt sie dahinter. Sonst
            // könnte die Mitte genau auf ihn fallen.
            if let foreign = foreignKeys.last(where: { key in key > (lower ?? "") && upper.map { key < $0 } ?? true }) {
                lower = foreign
            }
            guard let keys = try? FractionalIndex.keys(count: end - index, between: lower, and: upper) else {
                // Sollte nicht vorkommen (behaltene Schlüssel sind gültig und aufsteigend).
                // Sicherheitsnetz: alle Blöcke der Seite neu nummerieren, fremde dahinter,
                // damit kein Schlüssel doppelt vorkommt.
                let all = order + others.sorted { $0.sortKey < $1.sortKey }
                for (block, key) in zip(all, FractionalIndex.keys(count: all.count)) {
                    block.sortKey = key
                    block.updatedAt = .now
                }
                return true
            }
            for (block, key) in zip(order[index..<end], keys) {
                block.sortKey = key
                block.updatedAt = .now
            }
            changed = true
            index = end
        }
        return changed
    }

    /// Indizes einer längsten streng aufsteigenden Teilfolge gültiger Schlüssel (O(n log n)).
    static func longestIncreasingRun(_ keys: [String]) -> Set<Int> {
        var tails: [Int] = []
        var previous = [Int](repeating: -1, count: keys.count)
        for (index, key) in keys.enumerated() where FractionalIndex.isValid(key) {
            var low = 0
            var high = tails.count
            while low < high {
                let mid = (low + high) / 2
                if keys[tails[mid]] < key { low = mid + 1 } else { high = mid }
            }
            previous[index] = low > 0 ? tails[low - 1] : -1
            if low == tails.count { tails.append(index) } else { tails[low] = index }
        }
        var result = Set<Int>()
        var cursor = tails.last ?? -1
        while cursor >= 0 {
            result.insert(cursor)
            cursor = previous[cursor]
        }
        return result
    }
}

// MARK: - Bilder (ADR-015)

/// Ergebnis von `PageStore.importImage`.
public struct ImportedImage: Sendable, Equatable {
    public let assetID: UUID
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Das Original war größer als `ImageImport.maxOriginalBytes`.
    public let wasDownscaled: Bool
}

extension PageStore {
    /// Legt ein Asset an (GPS entfernt, ggf. verkleinert).
    ///
    /// Der Editor vergibt `assetID` schon beim Einfügen und zeigt bis zum Ende des
    /// Imports einen Platzhalter. Ist der Block `blockID` dann schon gespeichert, wird
    /// er hier verknüpft; sonst verknüpft ihn sein Speichern über `BlockProperties.assetID`.
    public func importImage(_ data: Data, assetID: UUID = UUID(), linkTo blockID: UUID? = nil) throws -> ImportedImage {
        let prepared = try ImageImport.prepare(data)
        let asset = Asset(data: prepared.data, uti: prepared.uti)
        asset.id = assetID
        asset.pixelWidth = prepared.pixelWidth
        asset.pixelHeight = prepared.pixelHeight
        modelContext.insert(asset)
        try save()
        if let blockID {
            var descriptor = FetchDescriptor<Block>(predicate: #Predicate { $0.id == blockID })
            descriptor.fetchLimit = 1
            if let block = try modelContext.fetch(descriptor).first, block.kind == .image, block.asset == nil {
                var properties = block.properties
                properties.assetID = assetID
                block.properties = properties
                try save()
            }
        }
        return ImportedImage(
            assetID: asset.id, pixelWidth: prepared.pixelWidth, pixelHeight: prepared.pixelHeight,
            wasDownscaled: prepared.wasDownscaled
        )
    }

    /// Kopie eines Assets, z. B. für eingesetzte Bild-Blöcke: Ein Asset gehört
    /// genau einem Block.
    public func duplicateAsset(_ id: UUID) throws -> UUID? {
        guard let original = try fetchAsset(id) else { return nil }
        let copy = original.makeCopy()
        modelContext.insert(copy)
        try save()
        return copy.id
    }

    /// Bilddaten und Typ, `nil`, wenn es das Asset nicht (mehr) gibt.
    public func imageData(_ id: UUID) throws -> (data: Data, uti: String)? {
        guard let asset = try fetchAsset(id), let data = asset.data else { return nil }
        return (data, asset.uti)
    }

    /// Löscht Assets ohne Block, die seit `age` nicht mehr verknüpft waren.
    /// Beim Start aufgerufen; 30 Tage wie der Papierkorb (ADR-015).
    @discardableResult
    public func removeOrphanedAssets(olderThan age: TimeInterval = 30 * 24 * 3600, now: Date = .now) throws -> Int {
        let cutoff = now.addingTimeInterval(-age)
        let orphans = try modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.block == nil && $0.updatedAt < cutoff }))
        for asset in orphans { modelContext.delete(asset) }
        try save()
        return orphans.count
    }

    private func fetchAsset(_ id: UUID) throws -> Asset? {
        var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
