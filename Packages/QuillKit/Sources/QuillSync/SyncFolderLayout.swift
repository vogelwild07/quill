import CryptoKit
import Foundation

/// `quill.json` im Sync-Ordner: Formatversion, Ordner-ID, verschlüsselt ja/nein (ADR-026).
public struct FolderManifest: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    public var format: Int
    /// Erkennt einen fremden Quill-Ordner: Passt die ID nicht zur verbundenen,
    /// wird nur nach Rückfrage zusammengeführt.
    public var folderID: UUID
    public var encrypted: Bool
    public var createdAt: Date

    public init(folderID: UUID = UUID(), encrypted: Bool = false, createdAt: Date = .now) {
        self.format = Self.currentFormat
        self.folderID = folderID
        self.encrypted = encrypted
        self.createdAt = createdAt
    }

    /// Liest `quill.json`. Neueres Format oder kaputte Daten werfen; der Ordner wird
    /// dann nicht beschrieben (ADR-026).
    public static func decode(_ data: Data) throws -> FolderManifest {
        let manifest: FolderManifest
        do {
            manifest = try SyncJSON.decoder.decode(FolderManifest.self, from: data)
        } catch {
            if let format = try? SyncJSON.decoder.decode(FormatOnly.self, from: data).format, format > currentFormat {
                throw SyncError.newerFormat(format)
            }
            throw SyncError.unreadable(String(describing: error))
        }
        guard manifest.format <= currentFormat else { throw SyncError.newerFormat(manifest.format) }
        return manifest
    }

    public func encoded() throws -> Data { try SyncJSON.encoder.encode(self) }

    private struct FormatOnly: Decodable { var format: Int }
}

/// `devices/<Geräte-ID>.json`: Name und zuletzt gesehen, für die Geräteliste.
public struct DeviceInfo: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var lastSeen: Date

    public init(id: UUID, name: String, lastSeen: Date = .now) {
        self.id = id
        self.name = name
        self.lastSeen = lastSeen
    }

    public static func decode(_ data: Data) throws -> DeviceInfo {
        do {
            return try SyncJSON.decoder.decode(DeviceInfo.self, from: data)
        } catch {
            throw SyncError.unreadable(String(describing: error))
        }
    }

    public func encoded() throws -> Data { try SyncJSON.encoder.encode(self) }
}

/// Pfade im Sync-Ordner nach ADR-026. Jedes Gerät schreibt nur unter seiner eigenen
/// Geräte-ID; Dateinamen enthalten nur UUIDs, Nummern und Prüfsummen, keine Titel.
///
/// ```
/// Quill/
///   quill.json
///   devices/<Geräte-ID>.json
///   tree/<Geräte-ID>/<Nr>.changes
///   tree/<Geräte-ID>/<Nr>.snapshot
///   pages/<Seiten-ID>/<Geräte-ID>/<Nr>.changes
///   pages/<Seiten-ID>/<Geräte-ID>/<Nr>.snapshot
///   assets/<SHA-256>.<Endung>
/// ```
///
/// Eine verdichtete Datei (`<Nr>.snapshot`) ist der ganze Stand des Dokuments samt
/// Geschichte und ersetzt alle eigenen Dateien bis zu ihrer Nummer (ADR-026).
public struct SyncFolderLayout: Equatable, Sendable {
    public static let folderName = "Quill"
    static let changesExtension = "changes"
    static let snapshotExtension = "snapshot"
    /// Stellen der Nummer im Dateinamen; sortiert damit auch im Finder richtig.
    static let numberDigits = 12

    /// Der Ordner `Quill` im gewählten Ordner.
    public let root: URL

    public init(chosenFolder: URL) {
        root = chosenFolder.appending(path: Self.folderName, directoryHint: .isDirectory)
    }

    public var manifest: URL { root.appending(path: "quill.json") }
    public var devices: URL { root.appending(path: "devices", directoryHint: .isDirectory) }
    public var tree: URL { root.appending(path: "tree", directoryHint: .isDirectory) }
    public var pages: URL { root.appending(path: "pages", directoryHint: .isDirectory) }
    public var assets: URL { root.appending(path: "assets", directoryHint: .isDirectory) }

    public func device(_ id: UUID) -> URL { devices.appending(path: "\(id.uuidString).json") }

    /// Änderungen des Seitenbaums von einem Gerät.
    public func tree(device: UUID) -> URL {
        tree.appending(path: device.uuidString, directoryHint: .isDirectory)
    }

    /// Änderungen einer Seite von einem Gerät.
    public func page(_ page: UUID, device: UUID) -> URL {
        pages.appending(path: page.uuidString, directoryHint: .isDirectory)
            .appending(path: device.uuidString, directoryHint: .isDirectory)
    }

    public static func changes(_ number: Int, in directory: URL) -> URL {
        directory.appending(path: changesFileName(number))
    }

    public static func snapshot(_ number: Int, in directory: URL) -> URL {
        directory.appending(path: fileName(number, snapshotExtension))
    }

    /// Bild nach Inhalt benannt: gleiche Daten ergeben denselben Namen, zwei Geräte
    /// schreiben dann dieselbe Datei mit demselben Inhalt.
    public func asset(_ data: Data, fileExtension: String) -> URL {
        assets.appending(path: "\(Self.sha256(data)).\(fileExtension.lowercased())")
    }

    static func changesFileName(_ number: Int) -> String { fileName(number, changesExtension) }

    private static func fileName(_ number: Int, _ fileExtension: String) -> String {
        let digits = String(number)
        return String(repeating: "0", count: max(0, numberDigits - digits.count)) + digits + "." + fileExtension
    }

    /// Nummer aus einem Dateinamen wie `000000000042.changes`; `nil` für alles andere.
    public static func changesNumber(_ fileName: String) -> Int? { number(fileName, changesExtension) }

    /// Nummer aus einem Dateinamen wie `000000000051.snapshot`; `nil` für alles andere.
    public static func snapshotNumber(_ fileName: String) -> Int? { number(fileName, snapshotExtension) }

    private static func number(_ fileName: String, _ fileExtension: String) -> Int? {
        let parts = fileName.split(separator: ".")
        guard parts.count == 2, parts[1] == fileExtension, parts[0].count == numberDigits,
              parts[0].allSatisfy(\.isASCII), let number = Int(parts[0]), number >= 0
        else { return nil }
        return number
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// JSON im Ordner: sortierte Schlüssel und ISO-8601-Daten, lesbar und stabil.
enum SyncJSON {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Was im gewählten Ordner schon liegt, gelesen ohne etwas zu schreiben: vor dem
/// Einschalten, um zu entscheiden, ob Quill zusammenführt oder neu beginnt (ADR-029).
public struct SyncFolderInspection: Equatable, Sendable {
    /// Der Ordner `Quill` fehlt oder ist leer.
    public var isEmpty: Bool
    /// ID aus `quill.json`; `nil`, wenn es die Datei nicht gibt oder sie (noch) nicht
    /// lesbar ist.
    public var folderID: UUID?

    public init(isEmpty: Bool, folderID: UUID?) {
        self.isEmpty = isEmpty
        self.folderID = folderID
    }

    public static func inspect(
        _ chosenFolder: URL, files: any SyncFileAccess = CoordinatedFileAccess()
    ) throws -> SyncFolderInspection {
        let layout = SyncFolderLayout(chosenFolder: chosenFolder)
        // Vom Finder angelegt, keine Quill-Daten.
        let entries = try files.contents(of: layout.root).filter { $0.name != ".DS_Store" }
        let manifest = entries.first { $0.name == layout.manifest.lastPathComponent }
        let folderID = manifest.flatMap { $0.isDownloaded ? try? FolderManifest.decode(files.read(layout.manifest)).folderID : nil }
        return SyncFolderInspection(isEmpty: entries.isEmpty, folderID: folderID)
    }
}
