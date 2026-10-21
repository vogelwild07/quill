import Foundation

/// Eintrag eines Ordners im Sync-Ordner.
public struct SyncFileEntry: Equatable, Sendable {
    /// Name der Datei, bei Platzhaltern von iCloud Drive (`.name.icloud`) der echte Name.
    public var name: String
    public var isDirectory: Bool
    /// `false`, solange ein Datei-Anbieter (iCloud Drive, Dropbox …) nur einen
    /// Platzhalter hat. Solche Dateien werden angefordert und erst danach gelesen.
    public var isDownloaded: Bool

    public init(name: String, isDirectory: Bool = false, isDownloaded: Bool = true) {
        self.name = name
        self.isDirectory = isDirectory
        self.isDownloaded = isDownloaded
    }
}

/// Lesen und Schreiben im Sync-Ordner (ADR-026). Austauschbar für Tests.
public protocol SyncFileAccess: Sendable {
    /// Einträge eines Ordners; leer, wenn es ihn nicht gibt.
    func contents(of directory: URL) throws -> [SyncFileEntry]
    func read(_ url: URL) throws -> Data
    /// Legt eine neue Datei an (Ordner davor auch). Gibt es sie schon, wirft es und
    /// lässt sie unverändert: Jedes Gerät hängt nur an, nie wird überschrieben.
    func create(_ url: URL, with data: Data) throws
    /// Ersetzt eine eigene Datei, die immer nur dieses Gerät schreibt (`devices/<ID>.json`).
    func replace(_ url: URL, with data: Data) throws
    /// Bittet den Datei-Anbieter, eine noch nicht geladene Datei zu laden.
    func requestDownload(_ url: URL) throws
    /// Löscht eine eigene Datei, die eine verdichtete Datei ersetzt (ADR-026). Nie
    /// für Dateien anderer Geräte. Gibt es sie nicht mehr, ist das kein Fehler.
    func delete(_ url: URL) throws
}

/// Echter Zugriff über `NSFileCoordinator`, damit Datei-Anbieter Lesen und Schreiben
/// mitbekommen. Nicht geladene Dateien werden nie koordiniert gelesen: Das würde
/// warten, bis sie geladen sind.
public struct CoordinatedFileAccess: SyncFileAccess {
    static let placeholderPrefix = "."
    static let placeholderSuffix = ".icloud"

    public init() {}

    public func contents(of directory: URL) throws -> [SyncFileEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .ubiquitousItemDownloadingStatusKey]
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        return try urls.map { url in
            let values = try url.resourceValues(forKeys: Set(keys))
            let name = url.lastPathComponent
            if let real = Self.placeholderTarget(name) {
                return SyncFileEntry(name: real, isDirectory: false, isDownloaded: false)
            }
            let status = values.ubiquitousItemDownloadingStatus
            return SyncFileEntry(
                name: name, isDirectory: values.isDirectory == true,
                isDownloaded: status == nil || status != .notDownloaded
            )
        }
    }

    /// Echter Name hinter einem Platzhalter `.name.icloud`, sonst `nil`.
    static func placeholderTarget(_ name: String) -> String? {
        guard name.hasPrefix(placeholderPrefix), name.hasSuffix(placeholderSuffix),
              name.count > placeholderPrefix.count + placeholderSuffix.count
        else { return nil }
        return String(name.dropFirst(placeholderPrefix.count).dropLast(placeholderSuffix.count))
    }

    public func read(_ url: URL) throws -> Data {
        try coordinate(.reading(url)) { try Data(contentsOf: $0) }
    }

    public func create(_ url: URL, with data: Data) throws {
        try coordinate(.writing(url, [])) { target in
            let folder = target.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Erst vollständig daneben schreiben, dann umbenennen: Andere Geräte sehen nie
            // eine halbe Datei, und `moveItem` scheitert, wenn es das Ziel schon gibt.
            let temporary = folder.appending(path: ".\(target.lastPathComponent).\(UUID().uuidString).tmp")
            try data.write(to: temporary)
            do {
                try FileManager.default.moveItem(at: temporary, to: target)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                throw error
            }
        }
    }

    public func replace(_ url: URL, with data: Data) throws {
        try coordinate(.writing(url, .forReplacing)) { target in
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        }
    }

    public func requestDownload(_ url: URL) throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    public func delete(_ url: URL) throws {
        try coordinate(.writing(url, .forDeleting)) { target in
            do {
                try FileManager.default.removeItem(at: target)
            } catch CocoaError.fileNoSuchFile {
            }
        }
    }

    private enum Access {
        case reading(URL)
        case writing(URL, NSFileCoordinator.WritingOptions)
    }

    /// Führt `work` innerhalb der Koordination aus und reicht Fehler aus beiden durch.
    private func coordinate<T>(_ access: Access, work: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, any Error>?
        switch access {
        case .reading(let url):
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in result = Result { try work(url) } }
        case .writing(let url, let options):
            coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { url in result = Result { try work(url) } }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
