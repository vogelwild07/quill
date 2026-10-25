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

    /// Version für einen Ordnernamen (ADR-037): nur Ziffern, Buchstaben, Punkt und
    /// Bindestrich, höchstens 20 Zeichen; sonst „unbekannt“. Die Version stammt aus der
    /// Versionsliste und darf keinen Pfad bilden.
    static func safeVersion(_ version: String) -> String {
        let allowed = version.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("a"..."z").contains($0) || ("A"..."Z").contains($0) || $0 == "." || $0 == "-" }
        guard allowed, (1...20).contains(version.count), !version.contains("..") else { return "unbekannt" }
        return version
    }
}
