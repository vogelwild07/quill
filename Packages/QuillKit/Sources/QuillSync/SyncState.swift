import Foundation
import Synchronization

/// „Sync pausieren“ (ADR-029): Vor jedem Schreiben in den Ordner fragt der Abgleich
/// hier nach. `pause()` wirkt sofort, auch mitten in einem laufenden Abgleich.
public final class SyncGate: Sendable {
    private let paused: Mutex<Bool>

    public init(paused: Bool = false) {
        self.paused = Mutex(paused)
    }

    public var isPaused: Bool { paused.withLock { $0 } }

    public func pause() { paused.withLock { $0 = true } }

    public func resume() { paused.withLock { $0 = false } }

    /// Wirft `SyncFailure.paused`, wenn pausiert.
    func checkWritable() throws {
        if isPaused { throw SyncFailure.paused }
    }
}

/// Warum ein Abgleich nicht lief oder abbrach. Am Ordner ist dann nichts verändert,
/// außer bei `paused` die Dateien, die schon vorher vollständig geschrieben waren.
public enum SyncFailure: Error, Equatable, Sendable {
    /// Pausiert; nichts weiter wird in den Ordner geschrieben.
    case paused
    /// Noch keine Geräte-ID im Store: Sync ist nicht eingeschaltet.
    case notEnabled
    /// Der Ordner enthält Quill-Daten mit einer anderen Ordner-ID als der verbundene
    /// (oder es ist noch keiner verbunden). Zusammengeführt wird nur nach Rückfrage
    /// (ADR-026): mit dieser ID als `connectedFolderID` erneut abgleichen.
    case unknownFolder(UUID)
    /// Der verbundene Ordner hat kein `quill.json` mehr (verschoben, gelöscht oder noch
    /// nicht geladen). Quill legt es nicht neu an.
    case folderMissing
    /// `quill.json` ist noch nicht geladen; angefordert, der nächste Abgleich versucht es wieder.
    case waitingForDownload
    /// `quill.json` stammt aus einer neueren Version von Quill.
    case newerFormat(Int)
    /// `quill.json` ist unlesbar; Beschreibung fürs Protokoll.
    case unreadableManifest(String)
}

/// Welche Dateien je Dokument und Gerät schon übernommen sind: die höchste Nummer
/// ohne Lücke davor. Liegt in `Workspace.syncCursors`.
struct SyncCursors: Codable, Equatable {
    static let treeKey = "tree"

    /// Dokument (`tree` oder Seiten-ID) → Geräte-ID → letzte übernommene Nummer.
    var read: [String: [String: Int]] = [:]
    /// Seiten-ID → `updatedAt` der Seite beim letzten Abgleich; spätere Änderungen
    /// machen die Seite für den nächsten Abgleich fällig.
    var synced: [String: Date] = [:]
    /// Dokumente, deren Stand samt Geschichte schon in diesem Ordner steht. Für alle
    /// anderen schreibt der nächste Abgleich als erste eigene Datei den ganzen Stand
    /// (ADR-029, 11.4): nach dem Wechsel auf einen anderen Ordner hat ein Gerät dort
    /// sonst nur Änderungen, deren Grundlage im vorherigen Ordner liegt.
    var inFolder: Set<String> = []
    /// Dokument → Geräte-ID → seit wann eine Lücke ohne verdichtete Datei besteht
    /// (`SyncGap`). Verschwindet, sobald es weitergeht.
    var gaps: [String: [String: Date]] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey { case read, synced, inFolder, gaps }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        read = try container.decodeIfPresent([String: [String: Int]].self, forKey: .read) ?? [:]
        synced = try container.decodeIfPresent([String: Date].self, forKey: .synced) ?? [:]
        inFolder = try container.decodeIfPresent(Set<String>.self, forKey: .inFolder) ?? []
        gaps = try container.decodeIfPresent([String: [String: Date]].self, forKey: .gaps) ?? [:]
    }

    /// Zeitpunkte als Zahl, ohne Rundung: `synced` muss `updatedAt` genau treffen, sonst
    /// wäre jede Seite bei jedem Abgleich fällig. Bis zum Review von 11.6 standen sie
    /// auf die Sekunde gerundet (ISO 8601) im Store; solche Daten werden noch gelesen.
    init(data: Data?) {
        self = data.flatMap { data in
            (try? Self.decoder.decode(SyncCursors.self, from: data)) ?? (try? SyncJSON.decoder.decode(SyncCursors.self, from: data))
        } ?? SyncCursors()
    }

    func encoded() throws -> Data {
        let encoder = SyncJSON.encoder
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(self)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    func last(_ document: String, device: UUID) -> Int {
        read[document]?[device.uuidString] ?? 0
    }

    mutating func setLast(_ number: Int, _ document: String, device: UUID) {
        read[document, default: [:]][device.uuidString] = number
    }

    /// Merkt den Beginn einer Lücke (oder löscht ihn) und gibt ihn zurück.
    mutating func gap(_ document: String, device: UUID, open: Bool, now: Date) -> Date? {
        guard open else {
            gaps[document]?[device.uuidString] = nil
            if gaps[document]?.isEmpty == true { gaps[document] = nil }
            return nil
        }
        if let since = gaps[document]?[device.uuidString] { return since }
        gaps[document, default: [:]][device.uuidString] = now
        return now
    }
}

/// Lücke in den Dateien eines Geräts ohne verdichtete Datei: Nummern fehlen, obwohl
/// spätere da sind, z. B. weil der Anbieter das Löschen alter Dateien vor der neuen
/// verdichteten Datei übertragen hat. Quill wartet; dauert es länger als
/// `SyncEngine.gapReportDelay`, steht die Lücke im Bericht.
public struct SyncGap: Hashable, Sendable {
    /// Seiten-ID oder `SyncReport.treeID`.
    public var document: UUID
    public var device: UUID
    public var since: Date

    public init(document: UUID, device: UUID, since: Date) {
        self.document = document
        self.device = device
        self.since = since
    }
}

/// Eine Datei, die sich nicht lesen ließ (kaputt, unvollständig, neueres Format). Sie
/// bleibt unverändert liegen und wird bei jedem Abgleich erneut versucht (ADR-026).
public struct UnreadableFile: Equatable, Sendable {
    /// Pfad im Ordner `Quill`, z. B. `pages/<Seite>/<Gerät>/000000000003.changes`.
    public var path: String
    public var reason: String
}

/// Ergebnis eines Abgleichs.
public struct SyncReport: Equatable, Sendable {
    public var folderID: UUID
    /// Zwei Werte für dasselbe Feld, je Seite; die ID des Seitenbaums ist `treeID`.
    public var conflicts: [UUID: [FieldConflict]] = [:]
    public var unreadable: [UnreadableFile] = []
    /// Dateien, die der Anbieter erst noch laden muss; der nächste Abgleich holt sie.
    public var waitingForDownload: [String] = []
    /// Seiten, die wegen einer Eingabe während des Abgleichs beim nächsten Mal drankommen.
    public var postponed: [UUID] = []
    /// Blöcke, die nach „Löschen gegen Bearbeiten“ wiederhergestellt wurden.
    public var restoredBlocks: [UUID] = []
    /// Seiten, die trotz Papierkorb auf einem anderen Gerät bleiben (hier bearbeitet).
    public var restoredPages: [UUID] = []
    /// Seiten, deren Inhalt sich durch Änderungen anderer Geräte geändert hat.
    public var changedPages: Set<UUID> = []
    /// Namen der Geräte aus `devices/` im Ordner, dazu dieses Gerät.
    public var devices: [UUID: String] = [:]
    /// Lücken, die schon länger als `SyncEngine.gapReportDelay` bestehen.
    public var gaps: [SyncGap] = []

    /// Schlüssel in `conflicts` für den Seitenbaum.
    public static let treeID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}

/// Wahl des Nutzers bei einem Konflikt: in welchem Dokument (Seite oder `SyncReport.treeID`),
/// welches Objekt und Feld, welcher Wert (`ConflictVersion.value`).
public struct ConflictChoice: Hashable, Sendable {
    public var documentID: UUID
    public var objectID: UUID
    public var field: String?
    public var value: String

    public init(documentID: UUID, objectID: UUID, field: String?, value: String) {
        self.documentID = documentID
        self.objectID = objectID
        self.field = field
        self.value = value
    }
}

/// Fortschritt beim Abgleich der Seiten (`done` von `total`).
public struct SyncProgress: Equatable, Sendable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}
