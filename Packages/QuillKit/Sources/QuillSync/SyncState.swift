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

    init() {}

    init(data: Data?) {
        self = data.flatMap { try? SyncJSON.decoder.decode(SyncCursors.self, from: $0) } ?? SyncCursors()
    }

    func encoded() throws -> Data { try SyncJSON.encoder.encode(self) }

    func last(_ document: String, device: UUID) -> Int {
        read[document]?[device.uuidString] ?? 0
    }

    mutating func setLast(_ number: Int, _ document: String, device: UUID) {
        read[document, default: [:]][device.uuidString] = number
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

    /// Schlüssel in `conflicts` für den Seitenbaum.
    public static let treeID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
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
