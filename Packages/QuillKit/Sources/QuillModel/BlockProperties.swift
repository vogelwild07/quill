import Foundation

/// Einfache Felder eines Blocks neben Art und Text, gebündelt an einer Stelle.
///
/// Ein neues Feld kommt nur hier dazu, in `Block.properties` (Spalten in `SchemaV1`
/// bzw. einer neuen Schema-Version) und in den Testdaten von
/// `BlockPropertiesRoundTripTests`. Editor, Snapshot und Textspeicher reichen den
/// Wert nur durch.
public struct BlockProperties: Hashable, Codable, Sendable {
    public var indent: Int
    public var isChecked: Bool
    public var codeLanguage: String?

    public init(indent: Int = 0, isChecked: Bool = false, codeLanguage: String? = nil) {
        self.indent = indent
        self.isChecked = isChecked
        self.codeLanguage = codeLanguage
    }
}
