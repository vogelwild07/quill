import Foundation

/// Inhalt von `Block.richText`: versioniertes JSON aus Runs mit Marks und Link.
///
/// Plattformneutral und lesbar für Export und Suche. `Block.text` bleibt der Klartext;
/// `richText` ist `nil`, solange ein Block keine Formatierung hat. Passt der Text der
/// Runs nicht zu `Block.text` (z. B. nach einer fremden Änderung), gilt `Block.text`
/// ohne Formatierung.
///
/// ```json
/// {"runs":[{"marks":[],"text":"Hallo "},{"marks":["bold"],"text":"Welt"}],"version":1}
/// ```
public struct RichText: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public struct Run: Codable, Equatable, Sendable {
        public var text: String
        /// Rohwerte, z. B. `bold`, `italic`, `code`, `strikethrough`. Unbekannte bleiben erhalten.
        public var marks: [String]
        public var link: String?

        public init(text: String, marks: [String] = [], link: String? = nil) {
            self.text = text
            self.marks = marks.sorted()
            self.link = link
        }
    }

    public var version: Int
    public var runs: [Run]

    public init(runs: [Run]) {
        self.version = Self.currentVersion
        self.runs = runs
    }

    /// Klartext aller Runs.
    public var plainText: String { runs.map(\.text).joined() }

    /// Stabile Kodierung (sortierte Schlüssel), damit gleicher Inhalt gleiche Bytes ergibt.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// `nil` bei unlesbaren Daten oder einer neueren Version mit anderem Aufbau.
    public static func decode(_ data: Data) -> RichText? {
        try? JSONDecoder().decode(RichText.self, from: data)
    }
}
