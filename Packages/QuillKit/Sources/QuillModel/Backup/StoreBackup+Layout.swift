import Darwin
import Foundation

/// Fehler beim Vorbereiten des Stores vor dem Öffnen (ADR-019). Quill öffnet dann
/// nicht, statt auf einen leeren Store auszuweichen.
public enum StoreLayoutError: Error, Equatable, CustomStringConvertible {
    /// Eine andere Quill-Instanz zieht gerade um oder spielt ein Backup ein.
    case locked
    /// Die Sperrdatei ließ sich nicht anlegen.
    case lockFailed(String)
    /// Beim Umzug liegt eine Datei schon im Zielordner; nichts wird überschrieben.
    case moveConflict(String)
    /// Reste eines unterbrochenen Vorgangs, die Quill nicht zuordnen kann.
    case leftover(String)

    public var description: String {
        switch self {
        case .locked: "Eine andere Quill-Instanz richtet gerade die Datenbank ein."
        case .lockFailed(let reason): "Sperre nicht möglich: \(reason)"
        case .moveConflict(let path): "Umzug angehalten, im Ziel liegt schon: \(path)"
        case .leftover(let path): "Unvollständiger Vorgang, Dateien liegen in: \(path)"
        }
    }
}

/// Ordner der Store-Dateien, Umzug aus dem alten Ort und Sperre (ADR-019).
///
/// ```
/// Quill/
///   Store/        Quill.store, -wal, -shm, .Quill_SUPPORT, Quill.store.version
///   Backups/
///   Store.lock    Sperre für Umzug und Wiederherstellen
/// ```
///
/// Bis Phase 7.1 lagen die Store-Dateien direkt in `Quill/`. Der Umzug legt vorher
/// ein Backup „vor-umzug“ an, verschiebt sie einzeln in `.Store-umzug/` und benennt
/// den Ordner zuletzt in `Store/` um. Es wird nur verschoben, nie gelöscht; bricht
/// der Umzug ab, macht der nächste Start dort weiter.
extension StoreBackup {
    /// `Quill/`: enthält `Store/`, `Backups/`, Sperre und Merker.
    var rootURL: URL {
        backupsURL.deletingLastPathComponent()
    }

    /// `Quill/Store/`.
    var storeDirectoryURL: URL {
        storeURL.deletingLastPathComponent()
    }

    var lockURL: URL {
        rootURL.appending(path: "Store.lock", directoryHint: .notDirectory)
    }

    var moveURL: URL {
        rootURL.appending(path: ".Store-umzug", directoryHint: .isDirectory)
    }

    /// Ort des Stores vor Phase 7.1.
    var legacyStoreURL: URL {
        rootURL.appending(path: storeURL.lastPathComponent, directoryHint: .notDirectory)
    }

    /// Ob die Store-Dateien in einem eigenen Ordner liegen (in einigen Tests nicht).
    private var usesStoreDirectory: Bool {
        storeDirectoryURL.standardizedFileURL.path(percentEncoded: false)
            != rootURL.standardizedFileURL.path(percentEncoded: false)
    }

    // MARK: - Beim Start

    /// Beim Start aufrufen, **bevor** Backups entstehen und der Container öffnet:
    /// unter Sperre umziehen (falls nötig) und ein vorgemerktes Backup einspielen.
    public func prepareStore(lockTimeout: TimeInterval = 30) throws -> RestoreOutcome? {
        let lock = try StoreLock(at: lockURL, timeout: lockTimeout)
        defer { lock.release() }
        try moveLegacyStoreIfNeeded()
        return applyPendingRestore()
    }

    /// Schritte des Umzugs, für den Test eines Abbruchs mittendrin.
    enum MoveStep: Hashable, Sendable {
        case backedUp
        case moved(String)
    }

    /// Zieht die Store-Dateien aus `Quill/` nach `Quill/Store/` um. Gibt das Backup
    /// „vor-umzug“ zurück, wenn eines entstand. `stoppingAfter` hält nach einem
    /// Schritt an, als bräche die App ab (Tests).
    @discardableResult
    func moveLegacyStoreIfNeeded(stoppingAfter stop: MoveStep? = nil) throws -> URL? {
        guard usesStoreDirectory else { return nil }
        let fileManager = FileManager.default
        var backup: URL?
        if !exists(moveURL) {
            // Liegt der Store schon in `Store/`, bleibt eine Datei im alten Ort unberührt.
            guard exists(legacyStoreURL), !exists(storeDirectoryURL) else { return nil }
            backup = try createBackup(reason: .beforeMove, of: legacyStoreURL)
            if stop == .backedUp { return backup }
            try fileManager.createDirectory(at: moveURL, withIntermediateDirectories: false)
        }
        for name in storeItemNames {
            let source = rootURL.appending(path: name)
            guard exists(source) else { continue }
            let target = moveURL.appending(path: name)
            guard !exists(target) else { throw StoreLayoutError.moveConflict(target.path(percentEncoded: false)) }
            try fileManager.moveItem(at: source, to: target)
            if stop == .moved(name) { return backup }
        }
        guard !exists(storeDirectoryURL) else {
            throw StoreLayoutError.leftover(moveURL.path(percentEncoded: false))
        }
        try fileManager.moveItem(at: moveURL, to: storeDirectoryURL)
        return backup
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}

/// Exklusive Sperre per `flock` auf eine Datei. Endet der Prozess, gibt das System
/// sie frei, auch nach einem Absturz.
final class StoreLock {
    private var descriptor: Int32

    init(at url: URL, timeout: TimeInterval) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        descriptor = open(url.path(percentEncoded: false), O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw StoreLayoutError.lockFailed(String(cString: strerror(errno))) }
        let deadline = Date.now.addingTimeInterval(timeout)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, Date.now < deadline else {
                close(descriptor)
                descriptor = -1
                throw StoreLayoutError.locked
            }
            usleep(50_000)
        }
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}
