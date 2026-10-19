import Foundation
import SwiftData

/// Seite mit Blöcken und Unterseiten als `Sendable`-Werttyp für den Export (ADR-018).
/// Bilddaten reisen nicht mit; der Export holt sie einzeln über `PageStore.imageData`.
public struct PageExportSnapshot: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var blocks: [BlockSnapshot]
    /// Typ (UTI) der Bilder dieser Seite je `Asset.id`. Fehlt ein Bild hier, gibt es
    /// sein Asset nicht (mehr).
    public var imageTypes: [UUID: String]
    /// Unterseiten in Sidebar-Reihenfolge, ohne Papierkorb.
    public var children: [PageExportSnapshot]

    public init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        blocks: [BlockSnapshot] = [],
        imageTypes: [UUID: String] = [:],
        children: [PageExportSnapshot] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.blocks = blocks
        self.imageTypes = imageTypes
        self.children = children
    }
}

extension PageStore {
    /// Seite (und auf Wunsch ihre Unterseiten) für den Export, in einem Lesevorgang.
    /// Seiten im Papierkorb werden nicht exportiert.
    public func exportSnapshot(of pageID: UUID, includeSubpages: Bool) throws -> PageExportSnapshot {
        let page = try fetchPage(pageID, prefetching: [\.blocks])
        guard !isInTrash(page) else { throw PageStoreError.pageNotFound(pageID) }
        if includeSubpages {
            try prefetchBlocks(ofSubtree: page)
        }
        return exportSnapshot(of: page, includeSubpages: includeSubpages)
    }

    /// Lädt Blöcke und Unterseiten aller Seiten unter `root` gesammelt. Sonst holt
    /// SwiftData beim Lesen jeden Block und jede Liste von Unterseiten einzeln nach, bei
    /// 1000 Seiten Zehntausende Abfragen (docs/performance.md). Ändert nichts am
    /// Ergebnis, nur am Zwischenspeicher.
    private func prefetchBlocks(ofSubtree root: Page) throws {
        let pages = try modelContext.fetch(FetchDescriptor<Page>())
        let byParent = Dictionary(grouping: pages) { $0.parent?.id }
        var ids: [UUID] = []
        var queue = [root.id]
        var seen: Set<UUID> = []
        while let id = queue.popLast() {
            guard seen.insert(id).inserted else { continue }
            ids.append(id)
            queue.append(contentsOf: (byParent[id] ?? []).map(\.id))
        }
        var descriptor = FetchDescriptor<Page>(predicate: #Predicate { ids.contains($0.id) })
        descriptor.relationshipKeyPathsForPrefetching = [\.blocks, \.children]
        _ = try modelContext.fetch(descriptor)
    }

    private func exportSnapshot(of page: Page, includeSubpages: Bool) -> PageExportSnapshot {
        let children = includeSubpages
            ? (page.children ?? [])
                .filter { $0.trashedAt == nil }
                .sortedInSiblingOrder(by: \.siblingOrder)
                .map { exportSnapshot(of: $0, includeSubpages: true) }
            : []
        let blocks = orderedBlocks(of: page)
        var imageTypes: [UUID: String] = [:]
        for block in blocks where block.kind == .image {
            if let asset = block.asset { imageTypes[asset.id] = asset.uti }
        }
        return PageExportSnapshot(
            id: page.id,
            title: page.title,
            createdAt: page.createdAt,
            updatedAt: page.updatedAt,
            blocks: blocks.map(\.snapshot),
            imageTypes: imageTypes,
            children: children
        )
    }
}
