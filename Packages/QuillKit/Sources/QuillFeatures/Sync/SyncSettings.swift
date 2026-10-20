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
}

/// Einstellungen des Sync, in den Einstellungen des Macs statt im Store (ADR-029):
/// Ein eingespieltes Backup schaltet den Sync so nie ein. Ohne gespeicherte Verbindung
/// ist der Sync aus; einschalten kann ihn nur der Nutzer.
@MainActor
public final class SyncSettings {
    static let connectionKey = "QuillSyncConnection"
    static let askAfterRestoreKey = "QuillSyncAskAfterRestore"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var connection: SyncConnection? {
        get { defaults.data(forKey: Self.connectionKey).flatMap { try? JSONDecoder().decode(SyncConnection.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.connectionKey)
            } else {
                defaults.removeObject(forKey: Self.connectionKey)
            }
        }
    }

    /// Der Sync wurde für ein Backup ausgeschaltet; nach dem Neustart fragt Quill, ob
    /// es als neues Gerät wieder verbinden soll.
    public var askAfterRestore: Bool {
        get { defaults.bool(forKey: Self.askAfterRestoreKey) }
        set { defaults.set(newValue, forKey: Self.askAfterRestoreKey) }
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
