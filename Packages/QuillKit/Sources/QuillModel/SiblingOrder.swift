import Foundation

/// Reihenfolge unter Geschwistern: Seiten einer Elternseite, Blöcke einer Seite,
/// Favoriten (ADR-009). Erst `sortKey`, bei Gleichstand das Anlagedatum, zuletzt die
/// `id`, damit alle Geräte auch bei doppelten Schlüsseln gleich sortieren.
///
/// Die einzige Stelle dieser Regel; Store, Sidebar und Export sortieren damit.
public struct SiblingOrder: Comparable, Sendable {
    public let sortKey: String
    public let createdAt: Date
    public let id: UUID

    /// Ein fehlender Schlüssel (z. B. Favorit ohne `favoriteSortKey`) gilt als leer.
    public init(sortKey: String?, createdAt: Date, id: UUID) {
        self.sortKey = sortKey ?? ""
        self.createdAt = createdAt
        self.id = id
    }

    /// Wie `(sortKey, createdAt, id.uuidString) < …`; die Zeichenkette der `id` entsteht
    /// nur bei Gleichstand der ersten beiden.
    public static func < (lhs: SiblingOrder, rhs: SiblingOrder) -> Bool {
        if lhs.sortKey != rhs.sortKey { return lhs.sortKey < rhs.sortKey }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

extension Sequence {
    /// Sortiert nach `SiblingOrder`. Stabil: Bei gleichem Schlüssel bleibt die
    /// bisherige Reihenfolge.
    ///
    /// Liest den Schlüssel einmal pro Element, nicht pro Vergleich: Bei SwiftData-Objekten
    /// kostet jeder Getter einige Mikrosekunden (`docs/performance.md`). Werttypen mit
    /// billigen Eigenschaften (`PageTree.Entry`) vergleichen besser direkt mit `<`.
    public func sortedInSiblingOrder(by order: (Element) -> SiblingOrder) -> [Element] {
        map { (order: order($0), element: $0) }
            .sorted { $0.order < $1.order }
            .map(\.element)
    }
}

extension Page {
    /// Platz unter den Geschwistern im Seitenbaum.
    public var siblingOrder: SiblingOrder {
        SiblingOrder(sortKey: sortKey, createdAt: createdAt, id: id)
    }

    /// Platz unter den Favoriten.
    public var favoriteOrder: SiblingOrder {
        SiblingOrder(sortKey: favoriteSortKey, createdAt: createdAt, id: id)
    }
}

extension Block {
    /// Platz in der Seite.
    public var siblingOrder: SiblingOrder {
        SiblingOrder(sortKey: sortKey, createdAt: createdAt, id: id)
    }
}
