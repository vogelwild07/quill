import Foundation
import QuillModel

/// Unveränderlicher Knoten des Seitenbaums für die Sidebar.
public struct PageNode: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var icon: String?
    public var children: [PageNode]

    public init(id: UUID, title: String, icon: String? = nil, children: [PageNode] = []) {
        self.id = id
        self.title = title
        self.icon = icon
        self.children = children
    }
}

/// Reine Funktionen rund um den Seitenbaum, ohne SwiftData und AppKit.
public enum PageTree {
    /// Was die Sidebar von einer Seite braucht.
    public struct Entry: Sendable {
        public let id: UUID
        public let parentID: UUID?
        public let title: String
        public let icon: String?
        public let sortKey: String
        public let createdAt: Date
        public let isFavorite: Bool
        public let favoriteSortKey: String?

        public init(
            id: UUID, parentID: UUID?, title: String, icon: String?, sortKey: String, createdAt: Date,
            isFavorite: Bool = false, favoriteSortKey: String? = nil
        ) {
            self.id = id
            self.parentID = parentID
            self.title = title
            self.icon = icon
            self.sortKey = sortKey
            self.createdAt = createdAt
            self.isFavorite = isFavorite
            self.favoriteSortKey = favoriteSortKey
        }

        @MainActor
        public init(_ page: Page) {
            self.init(
                id: page.id,
                parentID: page.parent?.id,
                title: page.title,
                icon: page.icon,
                sortKey: page.sortKey,
                createdAt: page.createdAt,
                isFavorite: page.isFavorite,
                favoriteSortKey: page.favoriteSortKey
            )
        }
    }

    /// Baut den Baum aus aktiven Seiten, ausgehend von der obersten Ebene. Seiten,
    /// deren Elternseite fehlt (z. B. im Papierkorb), werden so nie erreicht: Sie
    /// liegen logisch mit im Papierkorb.
    public static func build(_ entries: [Entry]) -> [PageNode] {
        let byParent = Dictionary(grouping: entries, by: \.parentID)

        func nodes(under parentID: UUID?) -> [PageNode] {
            (byParent[parentID] ?? [])
                .sorted { ($0.sortKey, $0.createdAt, $0.id.uuidString) < ($1.sortKey, $1.createdAt, $1.id.uuidString) }
                .map { PageNode(id: $0.id, title: $0.title, icon: $0.icon, children: nodes(under: $0.id)) }
        }
        return nodes(under: nil)
    }

    /// Favoriten in ihrer Reihenfolge, flach. Nur Seiten aus `tree`: Was (auch über
    /// eine Elternseite) im Papierkorb liegt, fehlt und kommt beim Wiederherstellen zurück.
    public static func favorites(_ entries: [Entry], in tree: [PageNode]) -> [PageNode] {
        entries
            .filter { $0.isFavorite && find($0.id, in: tree) != nil }
            .sorted { ($0.favoriteSortKey ?? "", $0.createdAt, $0.id.uuidString) < ($1.favoriteSortKey ?? "", $1.createdAt, $1.id.uuidString) }
            .map { PageNode(id: $0.id, title: $0.title, icon: $0.icon) }
    }

    /// Stelle für einen Drop an `index` unter Geschwistern `siblings` (wie angezeigt,
    /// inklusive der gezogenen Seite, falls sie dort schon liegt).
    public static func dropPosition(of dragged: UUID, into siblings: [UUID], at index: Int) -> SiblingPosition {
        let before = siblings.prefix(max(0, min(index, siblings.count))).filter { $0 != dragged }
        return before.last.map { .after($0) } ?? .first
    }

    /// Ob `candidate` die Seite `ancestor` selbst oder eine ihrer Unterseiten ist.
    public static func isSelfOrDescendant(_ candidate: UUID, of ancestor: UUID, in roots: [PageNode]) -> Bool {
        guard let node = find(ancestor, in: roots) else { return false }
        func contains(_ node: PageNode) -> Bool {
            node.id == candidate || node.children.contains(where: contains)
        }
        return contains(node)
    }

    /// Pfad der Vorfahren von `id`, oberste Ebene zuerst, ohne `id` selbst.
    public static func ancestors(of id: UUID, in roots: [PageNode]) -> [UUID]? {
        for node in roots {
            if node.id == id { return [] }
            if let path = ancestors(of: id, in: node.children) { return [node.id] + path }
        }
        return nil
    }

    public static func find(_ id: UUID, in roots: [PageNode]) -> PageNode? {
        for node in roots {
            if node.id == id { return node }
            if let found = find(id, in: node.children) { return found }
        }
        return nil
    }
}

/// Was ein Drop in der Sidebar bewirkt (ADR-017). Seiten aus dem Baum lassen sich
/// verschieben oder zu den Favoriten ziehen; Favoriten nur innerhalb der Favoriten.
public enum SidebarDrop: Equatable, Sendable {
    case movePage(parentID: UUID?, position: SiblingPosition)
    case addFavorite(SiblingPosition)
    case moveFavorite(SiblingPosition)

    /// Woher die gezogene Seite kommt.
    public enum Source: Sendable { case page, favorite }

    /// Worauf oder wohinein abgelegt wird.
    public enum Target: Sendable, Equatable {
        case favorites
        case favorite(UUID)
        case pages
        case page(UUID)
    }

    /// `childIndex` ist `nil` für einen Drop auf das Ziel selbst. `nil` als Ergebnis:
    /// nicht erlaubt (Zyklus, Favorit in den Baum, Favorit auf sich selbst).
    public static func resolve(
        _ dragged: UUID, from source: Source, onto target: Target, childIndex: Int?,
        favorites: [UUID], tree: [PageNode]
    ) -> SidebarDrop? {
        switch target {
        case .favorites:
            guard let childIndex else {
                return source == .page && !favorites.contains(dragged) ? .addFavorite(.last) : nil
            }
            return favoriteDrop(dragged, at: childIndex, favorites: favorites)
        case .favorite(let id):
            // Auf einen Favoriten: davor einordnen.
            guard id != dragged, let index = favorites.firstIndex(of: id) else { return nil }
            return favoriteDrop(dragged, at: index, favorites: favorites)
        case .pages:
            guard source == .page else { return nil }
            let position = childIndex.map { PageTree.dropPosition(of: dragged, into: tree.map(\.id), at: $0) } ?? .last
            return .movePage(parentID: nil, position: position)
        case .page(let id):
            guard source == .page, !PageTree.isSelfOrDescendant(id, of: dragged, in: tree) else { return nil }
            let siblings = PageTree.find(id, in: tree)?.children.map(\.id) ?? []
            let position = childIndex.map { PageTree.dropPosition(of: dragged, into: siblings, at: $0) } ?? .last
            return .movePage(parentID: id, position: position)
        }
    }

    private static func favoriteDrop(_ dragged: UUID, at index: Int, favorites: [UUID]) -> SidebarDrop {
        let position = PageTree.dropPosition(of: dragged, into: favorites, at: index)
        return favorites.contains(dragged) ? .moveFavorite(position) : .addFavorite(position)
    }
}
