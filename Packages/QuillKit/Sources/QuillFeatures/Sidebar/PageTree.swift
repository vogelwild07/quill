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

        public init(id: UUID, parentID: UUID?, title: String, icon: String?, sortKey: String, createdAt: Date) {
            self.id = id
            self.parentID = parentID
            self.title = title
            self.icon = icon
            self.sortKey = sortKey
            self.createdAt = createdAt
        }

        @MainActor
        public init(_ page: Page) {
            self.init(
                id: page.id,
                parentID: page.parent?.id,
                title: page.title,
                icon: page.icon,
                sortKey: page.sortKey,
                createdAt: page.createdAt
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
