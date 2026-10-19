import Foundation

/// Dateinamen für den Export (ADR-018): gültig auf APFS, in Obsidian und als
/// relativer Markdown-Link.
public enum ExportFileName {
    /// APFS erlaubt höchstens 255 Bytes (UTF-8) pro Namensteil.
    public static let maxBytes = 255

    /// Zeichen, die im Dateisystem (`/`, `:`), unter Windows/iCloud oder in
    /// Markdown-Links und Obsidian (`#`, `^`, `[`, `]`, `%`) Ärger machen.
    static let replacedCharacters: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "#", "^", "[", "]", "%"]
    static let replacement: Character = "-"
    /// Größer ist kein echtes Zeichen (längste Emoji-Folgen haben rund 30 Bytes),
    /// sondern z. B. ein Buchstabe mit Hunderten Akzenten. So ein Zeichen wird „-“,
    /// sonst könnte das Kürzen auf `maxBytes` einen leeren Namen ergeben.
    static let maxCharacterBytes = 64

    /// Titel als Namensbasis ohne Endung: unerlaubte Zeichen und Steuerzeichen
    /// ersetzt, Leerraum zusammengefasst, kein führender Punkt (versteckte Datei).
    /// Leer wird zu `untitled`.
    public static func base(for title: String, untitled: String) -> String {
        var result = ""
        var lastWasSpace = false
        for character in title {
            if character.isWhitespace || isInvisible(character) {
                if !lastWasSpace { result.append(" ") }
                lastWasSpace = true
                continue
            }
            lastWasSpace = false
            let replaced = replacedCharacters.contains(character) || String(character).utf8.count > maxCharacterBytes
            result.append(replaced ? replacement : character)
        }
        result = result.trimmingCharacters(in: .whitespaces)
        // Ein Punkt am Anfang macht die Datei unsichtbar; einer am Ende ist auf APFS harmlos.
        let dots = result.prefix { $0 == "." }.count
        result = String(repeating: replacement, count: dots) + result.dropFirst(dots)
        if result.isEmpty { return untitled }
        return result
    }

    /// Steuer- und Formatzeichen (Tabs, Zeilentrenner, unsichtbare Zeichen) werden
    /// ein Leerzeichen. U+200D (ZWJ) bleibt, sonst zerfallen zusammengesetzte Emoji.
    private static func isInvisible(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .control: true
            case .format: scalar.value != 0x200D
            default: false
            }
        }
    }

    /// `base` + `suffix` + `ext`, auf `maxBytes` gekürzt.
    public static func name(base: String, suffix: String = "", extension ext: String = "") -> String {
        stem(base: base, suffix: suffix, reservingExtension: ext) + (ext.isEmpty ? "" : "." + ext)
    }

    /// `base` + `suffix` so gekürzt, dass mit der Endung `ext` höchstens `maxBytes`
    /// herauskommen. Gekürzt wird nur die Basis und nur an Zeichengrenzen, damit
    /// kein Emoji oder Umlaut zerbricht.
    public static func stem(base: String, suffix: String = "", reservingExtension ext: String = "") -> String {
        let tail = suffix + (ext.isEmpty ? "" : "." + ext)
        let budget = maxBytes - tail.utf8.count
        var kept = ""
        var used = 0
        for character in base {
            let size = String(character).utf8.count
            guard used + size <= budget else { break }
            kept.append(character)
            used += size
        }
        // Kürzen kann Leerraum ans Ende bringen ("Titel 2" statt "Titel  2").
        kept = String(kept.reversed().drop { $0.isWhitespace }.reversed())
        return kept + suffix
    }

    /// Vergleichsschlüssel wie APFS: ohne Unterschied zwischen Groß-/Kleinschreibung
    /// und zwischen zusammengesetzten und zerlegten Umlauten. Letzteres leistet
    /// `String` selbst (Gleichheit und Hash sind kanonisch äquivalent); der Schlüssel
    /// darf deshalb nie als Bytes oder Scalars verglichen werden.
    public static func collisionKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive], locale: nil)
    }
}

/// Vergebene Namen in einem Ordner. Gleiche Titel bekommen „Titel 2“, „Titel 3“ …
struct ExportNameRegistry {
    private var taken: Set<String> = []

    init(reserved: [String] = []) {
        for name in reserved { taken.insert(ExportFileName.collisionKey(name)) }
    }

    /// Freier Name für alle Endungen in `extensions` zugleich: Eine Seite belegt
    /// „Titel.md“ und den Ordner „Titel“ für ihre Unterseiten. Gibt den Namen ohne
    /// Endung zurück.
    mutating func claim(base: String, extensions: [String]) -> String {
        var counter = 1
        while true {
            let suffix = counter == 1 ? "" : " \(counter)"
            // Gekürzt wird für die längste Endung, damit alle Namen denselben Stamm haben.
            let longest = extensions.max { $0.utf8.count < $1.utf8.count } ?? ""
            let stem = ExportFileName.stem(base: base, suffix: suffix, reservingExtension: longest)
            let keys = extensions.map { ExportFileName.collisionKey(stem + ($0.isEmpty ? "" : "." + $0)) }
            if keys.allSatisfy({ !taken.contains($0) }) {
                taken.formUnion(keys)
                return stem
            }
            counter += 1
        }
    }
}
