import Automerge
import Foundation
import QuillModel

/// Eine Seite im Seitenbaum, wie sie die Sync-Schicht abgleicht.
public struct PageRecord: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var icon: String?
    public var parentID: UUID?
    public var sortKey: String
    public var isFavorite: Bool
    public var favoriteSortKey: String?
    /// `nil` = aktiv.
    public var trashedAt: Date?
    /// Auf einem Gerät endgültig gelöscht. Andere Geräte legen die Seite nur in den
    /// Papierkorb; endgültig weg ist sie dort erst nach „Papierkorb leeren“ (ADR-029).
    public var deletedAt: Date?
    /// Rohwert von `PageKind`; unbekannte bleiben erhalten.
    public var kindRaw: String
    public var createdAt: Date
    /// Vom Sync wiederhergestellt (im Papierkorb auf einem Gerät, bearbeitet auf einem anderen).
    public var isRestored: Bool
    /// Stand des Seiten-Dokuments, als die Seite in den Papierkorb kam. Ein anderes Gerät
    /// erkennt daran, ob es die Seite seitdem bearbeitet hat (dann bleibt sie, ADR-029).
    public var trashedVersion: DocumentVersion?

    public init(
        id: UUID, title: String = "", icon: String? = nil, parentID: UUID? = nil, sortKey: String = "",
        isFavorite: Bool = false, favoriteSortKey: String? = nil, trashedAt: Date? = nil, deletedAt: Date? = nil,
        kindRaw: String = PageKind.page.rawValue, createdAt: Date = .now, isRestored: Bool = false,
        trashedVersion: DocumentVersion? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.parentID = parentID
        self.sortKey = sortKey
        self.isFavorite = isFavorite
        self.favoriteSortKey = favoriteSortKey
        self.trashedAt = trashedAt
        self.deletedAt = deletedAt
        self.kindRaw = kindRaw
        self.createdAt = createdAt
        self.isRestored = isRestored
        self.trashedVersion = trashedVersion
    }

    /// Aus dem Store; Grabstein und Stand beim Papierkorb kennt nur das Dokument.
    public init(_ page: PageSnapshot) {
        self.init(
            id: page.id, title: page.title, icon: page.icon, parentID: page.parentID, sortKey: page.sortKey,
            isFavorite: page.isFavorite, favoriteSortKey: page.favoriteSortKey, trashedAt: page.trashedAt,
            kindRaw: page.kindRaw, createdAt: page.createdAt, isRestored: page.isRestored
        )
    }

    /// Für den Store. Eine endgültig gelöschte Seite liegt dort im Papierkorb (ADR-029),
    /// außer sie wurde wiederhergestellt, weil dieses Gerät sie inzwischen bearbeitet hat.
    public var snapshot: PageSnapshot {
        PageSnapshot(
            id: id, title: title, icon: icon, parentID: parentID, sortKey: sortKey, isFavorite: isFavorite,
            favoriteSortKey: favoriteSortKey, trashedAt: trashedAt ?? (isRestored ? nil : deletedAt), kindRaw: kindRaw,
            createdAt: createdAt,
            isRestored: isRestored
        )
    }
}

/// Seitenbaum als Automerge-Dokument (ADR-026, ADR-029): `pages` ist eine Map von
/// Seiten-ID auf eine Map mit Titel, Icon, Eltern, `sortKey`, Favorit, Papierkorb,
/// Grabstein (`deleted`), Art, Anlagedatum und Marke „wiederhergestellt“. Seiten werden nie aus dem Dokument
/// entfernt; endgültig Gelöschtes bleibt als Grabstein, damit kein anderes Gerät
/// eine Seite ohne „Papierkorb leeren“ verliert.
public final class TreeDocument: SyncDocument {
    override class var itemsKey: String { "pages" }
    /// Felder, deren gleichzeitige Änderung der Nutzer entscheidet. Reihenfolge,
    /// Favorit und Papierkorb nicht: Dort geht kein Inhalt verloren, und Papierkorb
    /// gegen Bearbeiten entscheidet die Sync-Schicht (die Seite bleibt).
    static let conflictFields = ["title", "icon", "parent"]

    public func records() throws -> [PageRecord] {
        var result: [PageRecord] = []
        for (id, key) in itemKeys() {
            guard let map = try map(key) else { continue }
            let fields = try fields(of: map)
            var record = PageRecord(id: id)
            if case .Scalar(.String(let title))? = fields["title"] { record.title = title }
            if case .Scalar(.String(let icon))? = fields["icon"] { record.icon = icon }
            if case .Scalar(.String(let parent))? = fields["parent"] { record.parentID = UUID(uuidString: parent) }
            if case .Scalar(.String(let sortKey))? = fields["sortKey"] { record.sortKey = sortKey }
            if case .Scalar(.Boolean(let favorite))? = fields["favorite"] { record.isFavorite = favorite }
            if case .Scalar(.String(let key))? = fields["favoriteSortKey"] { record.favoriteSortKey = key }
            record.trashedAt = Self.date(fields["trashed"])
            record.deletedAt = Self.date(fields["deleted"])
            if case .Scalar(.String(let kind))? = fields["kind"] { record.kindRaw = kind }
            record.createdAt = Self.date(fields["created"]) ?? .distantPast
            if case .Scalar(.Boolean(let restored))? = fields["restored"] { record.isRestored = restored }
            if case .Scalar(.Bytes(let bytes))? = fields["trashedVersion"] { record.trashedVersion = DocumentVersion(data: bytes) }
            result.append(record)
        }
        return result.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Übernimmt `records` (neu oder geändert) und hält die Änderung als Commit fest.
    /// Seiten, die hier fehlen, bleiben unverändert; ein gesetzter Grabstein wird nie
    /// zurückgenommen. `true`, wenn sich etwas geändert hat.
    @discardableResult
    public func update(_ records: [PageRecord]) throws -> Bool {
        var changed = false
        for record in records {
            let key = record.id.uuidString
            let map: ObjId
            if let existing = try self.map(key) {
                map = existing
            } else {
                map = try document.putObject(obj: itemsID, key: key, ty: .Map)
                changed = true
            }
            let fields = try fields(of: map)
            changed = try set(map, "title", .String(record.title), current: fields["title"]) || changed
            changed = try set(map, "icon", record.icon.map { .String($0) }, current: fields["icon"]) || changed
            changed = try set(map, "parent", record.parentID.map { .String($0.uuidString) }, current: fields["parent"]) || changed
            changed = try set(map, "sortKey", .String(record.sortKey), current: fields["sortKey"]) || changed
            changed = try set(map, "favorite", .Boolean(record.isFavorite), current: fields["favorite"]) || changed
            changed = try set(map, "favoriteSortKey", record.favoriteSortKey.map { .String($0) }, current: fields["favoriteSortKey"]) || changed
            changed = try set(map, "trashed", record.trashedAt.map(Self.value), current: fields["trashed"]) || changed
            changed = try set(
                map, "trashedVersion", record.trashedAt == nil ? nil : record.trashedVersion.map { .Bytes($0.data) },
                current: fields["trashedVersion"]
            ) || changed
            if let deletedAt = record.deletedAt {
                changed = try set(map, "deleted", Self.value(deletedAt), current: fields["deleted"]) || changed
            }
            changed = try set(map, "kind", .String(record.kindRaw), current: fields["kind"]) || changed
            changed = try set(map, "created", Self.value(record.createdAt), current: fields["created"]) || changed
            changed = try set(map, "restored", record.isRestored ? .Boolean(true) : nil, current: fields["restored"]) || changed
        }
        if changed { document.commitWith() }
        return changed
    }

    /// Endgültig gelöscht auf diesem Gerät: Grabstein setzen, Papierkorb falls nötig;
    /// `trashedVersion` gilt nur, wenn die Seite hier noch nicht im Papierkorb stand.
    @discardableResult
    public func markDeleted(_ id: UUID, at date: Date = .now, trashedVersion: DocumentVersion? = nil) throws -> Bool {
        guard var record = try records().first(where: { $0.id == id }), record.deletedAt == nil else { return false }
        record.deletedAt = date
        if record.trashedAt == nil {
            record.trashedAt = date
            record.trashedVersion = trashedVersion
        }
        return try update([record])
    }

    public func conflicts() throws -> [FieldConflict] {
        try conflicts(in: Self.conflictFields)
    }

    /// Sekunden seit 2001 wie `Date` selbst: verlustfrei, damit ein Datum aus dem Store
    /// nach dem Lesen gleich bleibt (sonst sähe der Abgleich eine Änderung).
    private static func value(_ date: Date) -> ScalarValue { .F64(date.timeIntervalSinceReferenceDate) }

    private static func date(_ value: Value?) -> Date? {
        guard case .Scalar(.F64(let seconds))? = value else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
}
