import Foundation

/// Name eines Backup-Ordners in `Backups/`: `<Zeitpunkt>_<Anlass>`, bei doppeltem
/// Namen mit Zähler (`-2`). In Vormerkung und Markierung beim Wiederherstellen als
/// einfacher String gespeichert, wie vor diesem Typ (ADR-019).
public struct BackupName: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}
