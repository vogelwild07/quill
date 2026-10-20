import Foundation

/// Verbindung zum Sync-Ordner auf diesem Mac (ADR-029): Lesezeichen des Ordners,
/// Ordner-ID nach der Zustimmung, pausiert ja/nein.
public struct SyncConnection: Codable, Equatable, Sendable {
    /// Lesezeichen mit Sandbox-Zugriff (`SyncFolderBookmark`).
    public var bookmark: Data
    /// ID aus `quill.json`, sobald der Ordner verbunden ist; `nil` bis zum ersten
    /// Abgleich bzw. bis zur Zustimmung bei einem Ordner mit vorhandenen Daten.
    public var folderID: UUID?
    public var isPaused: Bool

    public init(bookmark: Data, folderID: UUID? = nil, isPaused: Bool = false) {
        self.bookmark = bookmark
        self.folderID = folderID
        self.isPaused = isPaused
    }

    /// Der Ordner aus dem Lesezeichen; `nil`, wenn es ihn nicht mehr gibt oder Quill
    /// ihn nicht öffnen darf.
    var folder: URL? { try? SyncFolderBookmark.resolve(bookmark).folder }
}

/// Wo die Einstellungen des Sync liegen: beim echten Store in den Einstellungen des
/// Macs, bei Test-Stores im Arbeitsspeicher oder im Testordner. Ein Debug-Build hat
/// dieselbe Bundle-ID wie die App; UI-Tests schrieben sonst in deren Einstellungen.
public protocol SyncSettingsStorage: AnyObject {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
}

extension UserDefaults: SyncSettingsStorage {
    public func setData(_ data: Data?, forKey key: String) {
        if let data { set(data, forKey: key) } else { removeObject(forKey: key) }
    }
}

/// Nur im Arbeitsspeicher, für `-QuillInMemoryStore`.
public final class MemorySyncSettingsStorage: SyncSettingsStorage {
    private var values: [String: Data] = [:]

    public init() {}

    public func data(forKey key: String) -> Data? { values[key] }
    public func setData(_ data: Data?, forKey key: String) { values[key] = data }
}

/// In einer JSON-Datei, für `-QuillStoreDirectory`: bleibt über Neustarts im Testordner.
public final class FileSyncSettingsStorage: SyncSettingsStorage {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    private var values: [String: Data] {
        get { (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) } ?? [:] }
        set {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(newValue).write(to: url, options: .atomic)
        }
    }

    public func data(forKey key: String) -> Data? { values[key] }
    public func setData(_ data: Data?, forKey key: String) { values[key] = data }
}

/// Einstellungen des Sync, außerhalb des Stores (ADR-029): Ein eingespieltes Backup
/// schaltet den Sync so nie ein. Ohne gespeicherte Verbindung ist der Sync aus;
/// einschalten kann ihn nur der Nutzer.
@MainActor
public final class SyncSettings {
    static let connectionKey = "QuillSyncConnection"
    static let askAfterRestoreKey = "QuillSyncAskAfterRestore"
    static let previousConnectionKey = "QuillSyncPreviousConnection"

    private let storage: any SyncSettingsStorage

    public init(storage: any SyncSettingsStorage = UserDefaults.standard) {
        self.storage = storage
    }

    public var connection: SyncConnection? {
        get { value(forKey: Self.connectionKey) }
        set { set(newValue, forKey: Self.connectionKey) }
    }

    /// Die Verbindung vor dem letzten Ausschalten: Mit diesem Ordner führt Quill beim
    /// Wiederverbinden zusammen, statt neu zu beginnen.
    public var previousConnection: SyncConnection? {
        get { value(forKey: Self.previousConnectionKey) }
        set { set(newValue, forKey: Self.previousConnectionKey) }
    }

    /// Der Sync wurde für ein Backup ausgeschaltet; nach dem Neustart fragt Quill, ob
    /// es mit dem bisherigen Ordner zusammenführen oder mit einem neuen beginnen soll.
    public var askAfterRestore: Bool {
        get { storage.data(forKey: Self.askAfterRestoreKey) != nil }
        set { storage.setData(newValue ? Data([1]) : nil, forKey: Self.askAfterRestoreKey) }
    }

    private func value(forKey key: String) -> SyncConnection? {
        storage.data(forKey: key).flatMap { try? JSONDecoder().decode(SyncConnection.self, from: $0) }
    }

    private func set(_ connection: SyncConnection?, forKey key: String) {
        storage.setData(connection.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}

/// Lesezeichen für den gewählten Ordner, damit Quill ihn nach einem Neustart in der
/// Sandbox wieder öffnen darf (`com.apple.security.files.bookmarks.app-scope`).
public enum SyncFolderBookmark {
    public static func make(for folder: URL) throws -> Data {
        #if canImport(AppKit)
        try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    /// Ordner zum Lesezeichen und ob es erneuert werden sollte (verschoben, umbenannt).
    public static func resolve(_ bookmark: Data) throws -> (folder: URL, isStale: Bool) {
        var isStale = false
        #if canImport(AppKit)
        let folder = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
        #else
        let folder = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #endif
        return (folder, isStale)
    }
}
