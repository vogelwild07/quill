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

    public static func < (lhs: SiblingOrder, rhs: SiblingOrder) -> Bool {
        (lhs.sortKey, lhs.createdAt, lhs.id.uuidString) < (rhs.sortKey, rhs.createdAt, rhs.id.uuidString)
    }
}

extension Sequence {
    /// Sortiert nach `SiblingOrder`. Stabil: Bei gleichem Schlüssel bleibt die
    /// bisherige Reihenfolge.
    public func sortedInSiblingOrder(by order: (Element) -> SiblingOrder) -> [Element] {
        sorted { order($0) < order($1) }
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
