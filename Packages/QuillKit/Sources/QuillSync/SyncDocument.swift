import Automerge
import Foundation

/// Stand eines Sync-Dokuments, ohne Automerge-Typen nach außen (ADR-026: andere
/// Module sehen keine Automerge-Typen).
public struct DocumentVersion: Hashable, Sendable {
    let heads: Set<ChangeHash>
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

    /// Vollständiger Stand, z. B. für den Store oder einen Snapshot im Ordner.
    public func save() -> Data { document.save() }

    /// Änderungen seit `version`, oder alle (`nil`); zum Anhängen an den Ordner.
    public func changes(since version: DocumentVersion?) throws -> Data {
        guard let version else { return document.encodeNewChanges() }
        return try document.encodeChangesSince(heads: version.heads)
    }

    /// Übernimmt Änderungen oder einen vollständigen Stand eines anderen Geräts.
    /// Schon bekannte Änderungen werden übersprungen.
    public func apply(changes: Data) throws {
        do {
            try document.applyEncodedChanges(encoded: changes)
        } catch {
            throw SyncError.unreadable(String(describing: error))
        }
    }

    // MARK: Hilfen für Unterklassen

    /// Alle Objekte, Schlüssel als UUID; Schlüssel ohne gültige UUID werden übergangen.
    func itemKeys() -> [(UUID, String)] {
        document.keys(obj: itemsID).compactMap { key in UUID(uuidString: key).map { ($0, key) } }
    }

    func map(_ key: String) throws -> ObjId? {
        guard case .Object(let id, .Map)? = try document.get(obj: itemsID, key: key) else { return nil }
        return id
    }

    func fields(of map: ObjId) throws -> [String: Value] {
        var fields: [String: Value] = [:]
        for (key, value) in try document.mapEntries(obj: map) { fields[key] = value }
        return fields
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
                result.append(FieldConflict(objectID: id, field: nil, values: versions.map(Self.describe).sorted()))
            }
            guard let map = try map(key) else { continue }
            for field in fields {
                let values = try document.getAll(obj: map, key: field)
                if values.count > 1 {
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
