import Automerge
import Foundation

/// Stand eines Sync-Dokuments, ohne Automerge-Typen nach außen (ADR-026: andere
/// Module sehen keine Automerge-Typen).
public struct DocumentVersion: Hashable, Sendable {
    let heads: Set<ChangeHash>

    init(heads: Set<ChangeHash>) {
        self.heads = heads
    }

    /// Zum Speichern, z. B. im Seitenbaum.
    public var data: Data { heads.raw() }

    /// `nil`, wenn `data` keine gültige Folge von Prüfsummen ist.
    public init?(data: Data) {
        guard let heads = data.heads() else { return nil }
        self.heads = heads
    }
}

/// Zwei oder mehr Werte für dasselbe Feld, von verschiedenen Geräten gleichzeitig
/// gesetzt. Beide bleiben gespeichert, bis der Nutzer wählt (ADR-026).
public struct FieldConflict: Hashable, Sendable {
    /// Seite (im Seitenbaum) oder Block (in einer Seite).
    public var objectID: UUID
    /// Feldname im Dokument, z. B. `title`, `kind`, `checked`; `nil` = das ganze
    /// Objekt gibt es in zwei Fassungen.
    public var field: String?
    /// Die Werte als Text, in fester Reihenfolge.
    public var values: [String]
}

/// Gemeinsamer Unterbau von Seiten- und Baum-Dokument.
///
/// Jedes Dokument beginnt mit derselben ersten Änderung (feste Akteurs-ID, feste Zeit):
/// Legen zwei Geräte dasselbe Dokument unabhängig an, ist diese Änderung auf beiden
/// byte-gleich, und Automerge führt sie als eine zusammen; sonst gäbe es die Wurzel-Map
/// zweimal. Danach schreibt jede Sitzung mit einer neuen Akteurs-ID, damit eine
/// Akteurs-ID nie zwei verschiedene Änderungen mit derselben Nummer erzeugt, auch nicht
/// nach einem eingespielten Backup oder einem Absturz zwischen Ordner und Store (ADR-029).
public class SyncDocument {
    /// Erste Änderung jedes Dokuments; nie ändern, sonst passen alte und neue Dokumente nicht zusammen.
    private static let baseActor = ActorId(uuid: UUID(uuidString: "51C0A2E8-0000-4000-8000-000000000000")!)
    private static let baseTime = Date(timeIntervalSince1970: 0)

    let document: Document
    /// Map mit den Objekten (Blöcke bzw. Seiten), Schlüssel ist die UUID.
    let itemsID: ObjId
    class var formatVersion: Int { 1 }
    class var itemsKey: String { fatalError("Unterklasse") }

    /// Neues, leeres Dokument.
    public required init() {
        let document = Document()
        document.actor = Self.baseActor
        // Kann bei einem leeren Dokument nicht scheitern.
        itemsID = try! document.putObject(obj: .ROOT, key: Self.itemsKey, ty: .Map)
        try! document.put(obj: .ROOT, key: "format", value: .Int(Int64(Self.formatVersion)))
        document.commitWith(message: nil, timestamp: Self.baseTime)
        document.actor = ActorId()
        self.document = document
    }

    /// Lädt ein gespeichertes Dokument (`save()`).
    public required init(bytes: Data) throws {
        try ChunkCheck.validate(bytes)
        let document: Document
        do {
            document = try Document(bytes)
        } catch {
            throw SyncError.unreadable(String(describing: error))
        }
        if case .Scalar(.Int(let format))? = try document.get(obj: .ROOT, key: "format"), format > Self.formatVersion {
            throw SyncError.newerFormat(Int(format))
        }
        guard case .Object(let id, .Map)? = try document.get(obj: .ROOT, key: Self.itemsKey) else {
            throw SyncError.malformed(Self.itemsKey)
        }
        document.actor = ActorId()
        self.document = document
        itemsID = id
    }

    public var version: DocumentVersion { DocumentVersion(heads: document.heads()) }

    /// Vollständiger Stand samt Geschichte, z. B. für den Store oder als erste eigene
    /// Datei in einem Ordner. `apply(changes:)` nimmt ihn wie Änderungen an.
    public func save() -> Data { document.save() }

    /// Nur die gemeinsame erste Änderung, sonst nichts.
    public var isEmpty: Bool { document.getHistory().count <= 1 }

    /// Änderungen seit `version`, oder alle (`nil`); zum Anhängen an den Ordner.
    public func changes(since version: DocumentVersion?) throws -> Data {
        guard let version else { return document.encodeNewChanges() }
        return try document.encodeChangesSince(heads: version.heads)
    }

    /// Übernimmt Änderungen oder einen vollständigen Stand eines anderen Geräts.
    /// Schon bekannte Änderungen werden übersprungen.
    public func apply(changes: Data) throws {
        try ChunkCheck.validate(changes)
        do {
            try document.applyEncodedChanges(encoded: changes)
        } catch {
            throw SyncError.unreadable(String(describing: error))
        }
    }

    // MARK: Hilfen für Unterklassen

    /// `true`, wenn das Dokument alle Änderungen bis `version` kennt.
    public func contains(_ version: DocumentVersion) -> Bool {
        version.heads.allSatisfy { document.change(hash: $0) != nil }
    }

    /// Alle Objekte, Schlüssel als UUID; Schlüssel ohne gültige UUID werden übergangen.
    /// Mit `heads` der Stand von damals.
    func itemKeys(at heads: Set<ChangeHash>? = nil) -> [(UUID, String)] {
        let keys = heads.map { document.keysAt(obj: itemsID, heads: $0) } ?? document.keys(obj: itemsID)
        return keys.compactMap { key in UUID(uuidString: key).map { ($0, key) } }
    }

    func map(_ key: String, at heads: Set<ChangeHash>? = nil) throws -> ObjId? {
        let value = try heads.map { try document.getAt(obj: itemsID, key: key, heads: $0) } ?? document.get(obj: itemsID, key: key)
        guard case .Object(let id, .Map)? = value else { return nil }
        return id
    }

    func fields(of map: ObjId, at heads: Set<ChangeHash>? = nil) throws -> [String: Value] {
        var fields: [String: Value] = [:]
        let entries = try heads.map { try document.mapEntriesAt(obj: map, heads: $0) } ?? document.mapEntries(obj: map)
        for (key, value) in entries { fields[key] = value }
        return fields
    }

    /// Änderungen, die seit `version` dazugekommen sind (z. B. durch `apply(changes:)`).
    func changes(after version: DocumentVersion) throws -> [Change] {
        let known = Set(try document.forkAt(heads: version.heads).getHistory())
        return document.getHistory().filter { !known.contains($0) }.compactMap { document.change(hash: $0) }
    }

    /// Setzt ein Feld, nur wenn es sich ändert; `nil` entfernt es. `true`, wenn geändert.
    /// Gibt es mehrere Werte (Konflikt), wird immer geschrieben: Das löst ihn auf, auch
    /// wenn der gewählte Wert der ist, den Automerge gerade vorne zeigt.
    @discardableResult
    func set(_ map: ObjId, _ key: String, _ value: ScalarValue?, current: Value?) throws -> Bool {
        switch (value, current) {
        case (nil, nil):
            return false
        case (nil, _):
            try document.delete(obj: map, key: key)
            return true
        case (let value?, .Scalar(let old)?) where old == value:
            guard try document.getAll(obj: map, key: key).count > 1 else { return false }
            try document.put(obj: map, key: key, value: value)
            return true
        case (let value?, _):
            try document.put(obj: map, key: key, value: value)
            return true
        }
    }

    /// Konflikte in `fields` der Objekte und doppelte Objekte (`field == nil`).
    func conflicts(in fields: [String]) throws -> [FieldConflict] {
        var result: [FieldConflict] = []
        for (id, key) in itemKeys() {
            let versions = try document.getAll(obj: itemsID, key: key)
            if versions.count > 1 {
                // Zwei Objekte unter derselben ID sind immer ein Konflikt, auch wenn sie
                // gleich aussehen: Ihr Inhalt kann sich unterscheiden.
                result.append(FieldConflict(objectID: id, field: nil, values: versions.map(Self.describe).sorted()))
            }
            guard let map = try map(key) else { continue }
            for field in fields {
                let values = try document.getAll(obj: map, key: field)
                // Zwei Geräte haben denselben Wert gesetzt: kein Konflikt für den Nutzer.
                if Set(values.map(Self.describe)).count > 1 {
                    result.append(FieldConflict(objectID: id, field: field, values: values.map(Self.describe).sorted()))
                }
            }
        }
        return result.sorted { ($0.objectID.uuidString, $0.field ?? "") < ($1.objectID.uuidString, $1.field ?? "") }
    }

    static func describe(_ value: Value) -> String {
        switch value {
        case .Scalar(.String(let text)): text
        case .Scalar(.Int(let number)): String(number)
        case .Scalar(.Uint(let number)): String(number)
        case .Scalar(.F64(let number)): String(number)
        case .Scalar(.Boolean(let flag)): String(flag)
        case .Scalar(.Null): "null"
        case .Scalar(let other): String(describing: other)
        case .Object(let id, let type): "\(type) \(id)"
        }
    }
}
