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
    /// Die Fassungen, nach Wert sortiert; jeder Wert nur einmal.
    public var versions: [ConflictVersion]

    public init(objectID: UUID, field: String?, versions: [ConflictVersion]) {
        self.objectID = objectID
        self.field = field
        self.versions = versions
    }

    /// Die Werte als Text, in fester Reihenfolge.
    public var values: [String] { versions.map(\.value) }
}

/// Eine Fassung in einem Konflikt.
public struct ConflictVersion: Hashable, Sendable {
    /// Der Wert als Text (`SyncDocument.describe`); `resolve` nimmt ihn zum Wählen.
    public var value: String
    /// Das Gerät, das den Wert geschrieben hat; `nil`, wenn die Änderung es nicht nennt
    /// (vor 11.6 geschrieben).
    public var device: UUID?
    /// Nur bei einem doppelten Objekt: Text des Blocks bzw. Titel der Seite in dieser Fassung.
    public var summary: String?

    public init(value: String, device: UUID? = nil, summary: String? = nil) {
        self.value = value
        self.device = device
        self.summary = summary
    }
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

    /// Schreibt ab jetzt als `device`: Die Akteurs-ID beginnt mit der Geräte-ID, dahinter
    /// steht eine neue Sitzungs-ID. So nennt jede Änderung ihr Gerät, und die Wahl bei
    /// einem Konflikt kann zu jeder Fassung das Gerät zeigen (ADR-029).
    public func write(as device: UUID) {
        document.actor = Self.actor(device: device)
    }

    /// Schreibt ab jetzt in der Sitzung `session`, mit Gerät wie `write(as:)`; ohne Gerät
    /// (Sync nie eingeschaltet) nennen die Änderungen keins. Dieselbe Sitzung nach erneutem
    /// Laden zählt die Nummern ihrer Änderungen weiter, solange das geladene Dokument alle
    /// bisherigen Änderungen der Sitzung enthält (`HistoryRecorder`): So kommt nicht bei
    /// jeder Aufzeichnung eine neue Akteurs-ID ins Dokument.
    public func write(as device: UUID?, session: UUID) {
        document.actor = Self.actor(device: device, session: session)
    }

    static func actor(device: UUID, session: UUID = UUID()) -> ActorId {
        let bytes = withUnsafeBytes(of: device.uuid) { Data($0) } + withUnsafeBytes(of: session.uuid) { Data($0) }
        // 32 Byte, unter der Grenze von 128.
        return ActorId(data: bytes)!
    }

    static func actor(device: UUID?, session: UUID) -> ActorId {
        guard let device else { return ActorId(uuid: session) }
        return actor(device: device, session: session)
    }

    /// Geräte-ID aus einer Akteurs-ID von `actor(device:)`; `nil` für andere.
    static func device(of actor: ActorId) -> UUID? {
        let hex = Array(actor.description.utf8)
        guard hex.count == 64 else { return nil }
        var bytes: [UInt8] = []
        for index in stride(from: 0, to: 32, by: 2) {
            guard let byte = UInt8(String(decoding: hex[index..<index + 2], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(byte)
        }
        return bytes.withUnsafeBufferPointer { NSUUID(uuidBytes: $0.baseAddress) as UUID }
    }

    /// Akteur und Gerät jeder Änderung nach der gemeinsamen ersten, in der Reihenfolge der Geschichte.
    var changeAuthors: [(actor: String, device: UUID?)] {
        document.getHistory().dropFirst().compactMap { document.change(hash: $0) }.map { ($0.actorId.description, Self.device(of: $0.actorId)) }
    }

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
    /// Ein Konflikt (mehrere Werte) bleibt bestehen, solange der Wert gleich dem ist,
    /// den Automerge vorne zeigt: Der Store hat ihn nur übernommen, gewählt hat der
    /// Nutzer nichts (ADR-026, „bis dahin bleiben beide gespeichert“).
    @discardableResult
    func set(_ map: ObjId, _ key: String, _ value: ScalarValue?, current: Value?) throws -> Bool {
        switch (value, current) {
        case (nil, nil):
            return false
        case (nil, _):
            try document.delete(obj: map, key: key)
            return true
        case (let value?, .Scalar(let old)?) where old == value:
            return false
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
                let described = try versions.map { version in
                    var summary: String?
                    if case .Object(let map, .Map) = version { summary = try self.summary(of: map) }
                    return ConflictVersion(value: Self.describe(version), summary: summary)
                }
                result.append(FieldConflict(objectID: id, field: nil, versions: withDevices(described, obj: itemsID, key: key)))
            }
            guard let map = try map(key) else { continue }
            for field in fields {
                let values = Set(try document.getAll(obj: map, key: field).map(Self.describe))
                // Zwei Geräte haben denselben Wert gesetzt: kein Konflikt für den Nutzer.
                if values.count > 1 {
                    let described = values.map { ConflictVersion(value: $0) }
                    result.append(FieldConflict(objectID: id, field: field, versions: withDevices(described, obj: map, key: field)))
                }
            }
        }
        return result.sorted { ($0.objectID.uuidString, $0.field ?? "") < ($1.objectID.uuidString, $1.field ?? "") }
    }

    /// Ergänzt je Fassung das Gerät: aus der jüngsten Änderung, nach der es den Wert
    /// gibt und davor nicht. Nur bei Konflikten, also selten; dann einmal durch die Geschichte.
    private func withDevices(_ versions: [ConflictVersion], obj: ObjId, key: String) -> [ConflictVersion] {
        var open = Set(versions.map(\.value))
        var devices: [String: UUID] = [:]
        for hash in document.getHistory().reversed() where !open.isEmpty {
            guard let change = document.change(hash: hash),
                  let now = try? document.getAllAt(obj: obj, key: key, heads: [hash])
            else { continue }
            let before = Set(((try? document.getAllAt(obj: obj, key: key, heads: Set(change.deps))) ?? []).map(Self.describe))
            for value in now.map(Self.describe) where open.contains(value) && !before.contains(value) {
                open.remove(value)
                if let device = Self.device(of: change.actorId) { devices[value] = device }
            }
        }
        return versions.map { version in
            var version = version
            version.device = devices[version.value]
            return version
        }.sorted { $0.value < $1.value }
    }

    /// Kurzer Inhalt einer Fassung eines doppelten Objekts.
    func summary(of map: ObjId) throws -> String? { nil }

    /// Wahl des Nutzers bei einem Konflikt (ADR-026): schreibt `value` neu, auch wenn
    /// Automerge ihn schon vorne zeigt; danach gibt es nur noch diesen Wert. Bei einem
    /// doppelten Objekt (`field == nil`) bleibt die gewählte Fassung. `false`, wenn es
    /// den Konflikt oder den Wert nicht (mehr) gibt.
    @discardableResult
    public func resolve(_ objectID: UUID, field: String?, choosing value: String) throws -> Bool {
        let key = objectID.uuidString
        if let field {
            guard let map = try map(key) else { return false }
            let values = try document.getAll(obj: map, key: field)
            guard Set(values.map(Self.describe)).count > 1,
                  case .Scalar(let chosen)? = values.first(where: { Self.describe($0) == value })
            else { return false }
            try document.put(obj: map, key: field, value: chosen)
        } else {
            let versions = try document.getAll(obj: itemsID, key: key)
            guard versions.count > 1, case .Object(let chosen, .Map)? = versions.first(where: { Self.describe($0) == value }) else {
                return false
            }
            try rewrite(key, from: chosen)
        }
        document.commitWith()
        return true
    }

    /// Legt das Objekt unter `key` neu an, mit dem Inhalt der Fassung `map`.
    func rewrite(_ key: String, from map: ObjId) throws { fatalError("Unterklasse") }

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
