import Foundation

extension NSAttributedString.Key {
    /// Block-ID (`String`, UUID). Liegt auf jedem Zeichen eines Absatzes inkl. `\n`.
    static let quillBlockID = NSAttributedString.Key("de.vogel.quill.blockID")
    /// `BlockKind.rawValue`.
    static let quillBlockKind = NSAttributedString.Key("de.vogel.quill.blockKind")
    static let quillIndent = NSAttributedString.Key("de.vogel.quill.indent")
    static let quillChecked = NSAttributedString.Key("de.vogel.quill.checked")
    static let quillCodeLanguage = NSAttributedString.Key("de.vogel.quill.codeLanguage")
    /// Nummer eines nummerierten Punkts; abgeleitet, wird nach jeder Änderung nachgeführt.
    static let quillOrdinal = NSAttributedString.Key("de.vogel.quill.ordinal")
    /// Inline-Marks eines Zeichens: sortierte Rohwerte, durch Leerzeichen getrennt (`"bold italic"`).
    /// Zusammen mit `.link` die Wahrheit über die Formatierung; Schrift, Hintergrund
    /// und Durchstreichung werden daraus abgeleitet.
    static let quillMarks = NSAttributedString.Key("de.vogel.quill.marks")
}

/// Zeichen im Textspeicher.
enum StorageCharacter {
    static let paragraphEnd: unichar = 0x0A
    /// Weicher Umbruch (⇧↩, Code) – im Modell `\n`.
    static let softBreak = "\u{2028}"
    static let attachment = "\u{FFFC}"
}
