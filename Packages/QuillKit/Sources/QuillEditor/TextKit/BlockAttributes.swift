import Foundation
import QuillModel

extension NSAttributedString.Key {
    /// Block-ID (`String`, UUID). Liegt auf jedem Zeichen eines Absatzes inkl. `\n`.
    static let quillBlockID = NSAttributedString.Key("io.github.vogelwild07.quill.blockID")
    /// `BlockKind.rawValue`.
    static let quillBlockKind = NSAttributedString.Key("io.github.vogelwild07.quill.blockKind")
    /// `BlockProperties`, nur über `textAttributes` / `init(textAttributes:)` lesen und schreiben.
    static let quillIndent = NSAttributedString.Key("io.github.vogelwild07.quill.indent")
    static let quillChecked = NSAttributedString.Key("io.github.vogelwild07.quill.checked")
    static let quillCodeLanguage = NSAttributedString.Key("io.github.vogelwild07.quill.codeLanguage")
    /// `Asset.id` als `String`.
    static let quillAssetID = NSAttributedString.Key("io.github.vogelwild07.quill.assetID")
    /// Nummer eines nummerierten Punkts; abgeleitet, wird nach jeder Änderung nachgeführt.
    static let quillOrdinal = NSAttributedString.Key("io.github.vogelwild07.quill.ordinal")
    /// Inline-Marks eines Zeichens: sortierte Rohwerte, durch Leerzeichen getrennt (`"bold italic"`).
    /// Zusammen mit `.link` die Wahrheit über die Formatierung; Schrift, Hintergrund
    /// und Durchstreichung werden daraus abgeleitet.
    static let quillMarks = NSAttributedString.Key("io.github.vogelwild07.quill.marks")
}

extension BlockProperties {
    /// Die einzige Abbildung auf Textattribute. Ein Schlüssel pro Feld mit `Int`,
    /// `Bool` oder `String`, kein Struct als Wert: AppKit muss den Text archivieren
    /// können (ADR-014).
    var textAttributes: [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .quillIndent: indent,
            .quillChecked: isChecked,
        ]
        if let codeLanguage { attributes[.quillCodeLanguage] = codeLanguage }
        if let assetID { attributes[.quillAssetID] = assetID.uuidString }
        return attributes
    }

    init(textAttributes attributes: [NSAttributedString.Key: Any]) {
        self.init(
            indent: attributes[.quillIndent] as? Int ?? 0,
            isChecked: attributes[.quillChecked] as? Bool ?? false,
            codeLanguage: attributes[.quillCodeLanguage] as? String,
            assetID: (attributes[.quillAssetID] as? String).flatMap(UUID.init(uuidString:))
        )
    }
}

/// Zeichen im Textspeicher.
enum StorageCharacter {
    static let paragraphEnd: unichar = 0x0A
    /// Weicher Umbruch (⇧↩, Code) – im Modell `\n`.
    static let softBreak = "\u{2028}"
    static let attachment = "\u{FFFC}"
}
