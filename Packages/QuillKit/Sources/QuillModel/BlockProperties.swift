import Foundation

/// Einfache Felder eines Blocks neben Art und Text, gebündelt an einer Stelle.
///
/// Ein neues Feld kommt nur hier dazu, in `Block.properties` (Spalten oder Beziehungen
/// in `SchemaV2` bzw. einer neuen Schema-Version) und in den Testdaten von
/// `BlockPropertiesRoundTripTests`. Editor, Snapshot und Textspeicher reichen den
/// Wert nur durch.
public struct BlockProperties: Hashable, Codable, Sendable {
    public var indent: Int
    public var isChecked: Bool
    public var codeLanguage: String?
    /// Bild eines Bild-Blocks (`Asset.id`). Die Daten selbst reisen nie mit (ADR-015).
    public var assetID: UUID?
    /// Vom Sync wiederhergestellt: auf einem Gerät gelöscht, auf einem anderen
    /// gleichzeitig bearbeitet (ADR-026, ADR-029). Der Editor zeigt eine Marke.
    public var isRestored: Bool

    public init(
        indent: Int = 0, isChecked: Bool = false, codeLanguage: String? = nil, assetID: UUID? = nil,
        isRestored: Bool = false
    ) {
        self.indent = indent
        self.isChecked = isChecked
        self.codeLanguage = codeLanguage
        self.assetID = assetID
        self.isRestored = isRestored
    }

    private enum CodingKeys: String, CodingKey {
        case indent, isChecked, codeLanguage, assetID, isRestored
    }

    /// Fehlende Felder bekommen ihren Standard: Daten älterer Versionen (z. B. in der
    /// Zwischenablage) kennen neuere Felder nicht.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            indent: try container.decodeIfPresent(Int.self, forKey: .indent) ?? 0,
            isChecked: try container.decodeIfPresent(Bool.self, forKey: .isChecked) ?? false,
            codeLanguage: try container.decodeIfPresent(String.self, forKey: .codeLanguage),
            assetID: try container.decodeIfPresent(UUID.self, forKey: .assetID),
            isRestored: try container.decodeIfPresent(Bool.self, forKey: .isRestored) ?? false
        )
    }
}
