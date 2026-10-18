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

    private func isInTrash(_ page: Page) -> Bool {
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

        let lower = index > 0 ? siblings[index - 1].sortKey : nil
        let upper = index < siblings.count ? siblings[index].sortKey : nil
        if let key = try? FractionalIndex.key(between: lower, and: upper),
           lower.map(FractionalIndex.isValid) ?? true,
           upper.map(FractionalIndex.isValid) ?? true {
            return key
        }

        let keys = FractionalIndex.keys(count: siblings.count + 1)
        for (sibling, key) in zip(siblings, keys.enumerated().filter { $0.offset != index }.map(\.element)) {
            sibling.sortKey = key
            sibling.updatedAt = .now
        }
        return keys[index]
    }
}
