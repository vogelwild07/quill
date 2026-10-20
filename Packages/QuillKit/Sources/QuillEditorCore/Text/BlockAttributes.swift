import Foundation
import QuillModel

extension NSAttributedString.Key {
    /// Block-ID (`String`, UUID). Liegt auf jedem Zeichen eines Absatzes inkl. `\n`.
    package static let quillBlockID = NSAttributedString.Key("io.github.vogelwild07.quill.blockID")
    /// `BlockKind.rawValue`.
    package static let quillBlockKind = NSAttributedString.Key("io.github.vogelwild07.quill.blockKind")
    /// `BlockProperties`, nur über `textAttributes` / `init(textAttributes:)` lesen und schreiben.
    package static let quillIndent = NSAttributedString.Key("io.github.vogelwild07.quill.indent")
    package static let quillChecked = NSAttributedString.Key("io.github.vogelwild07.quill.checked")
    package static let quillCodeLanguage = NSAttributedString.Key("io.github.vogelwild07.quill.codeLanguage")
    /// Vom Sync wiederhergestellt (`Bool`).
    package static let quillRestored = NSAttributedString.Key("io.github.vogelwild07.quill.restored")
    /// `Asset.id` als `String`.
    package static let quillAssetID = NSAttributedString.Key("io.github.vogelwild07.quill.assetID")
    /// Nummer eines nummerierten Punkts; abgeleitet, wird nach jeder Änderung nachgeführt.
    package static let quillOrdinal = NSAttributedString.Key("io.github.vogelwild07.quill.ordinal")
    /// Inline-Marks eines Zeichens: sortierte Rohwerte, durch Leerzeichen getrennt (`"bold italic"`).
    /// Zusammen mit `.link` die Wahrheit über die Formatierung; Schrift, Hintergrund
    /// und Durchstreichung werden daraus abgeleitet.
    package static let quillMarks = NSAttributedString.Key("io.github.vogelwild07.quill.marks")
}

extension BlockProperties {
    /// Die einzige Abbildung auf Textattribute. Ein Schlüssel pro Feld mit `Int`,
    /// `Bool` oder `String`, kein Struct als Wert: AppKit muss den Text archivieren
    /// können (ADR-014).
    package var textAttributes: [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .quillIndent: indent,
            .quillChecked: isChecked,
            .quillRestored: isRestored,
        ]
        if let codeLanguage { attributes[.quillCodeLanguage] = codeLanguage }
        if let assetID { attributes[.quillAssetID] = assetID.uuidString }
        return attributes
    }

    package init(textAttributes attributes: [NSAttributedString.Key: Any]) {
        self.init(
            indent: attributes[.quillIndent] as? Int ?? 0,
            isChecked: attributes[.quillChecked] as? Bool ?? false,
            codeLanguage: attributes[.quillCodeLanguage] as? String,
            assetID: (attributes[.quillAssetID] as? String).flatMap(UUID.init(uuidString:)),
            isRestored: attributes[.quillRestored] as? Bool ?? false
        )
    }
}

/// Zeichen im Textspeicher.
package enum StorageCharacter {
    package static let paragraphEnd: unichar = 0x0A
    /// Weicher Umbruch (⇧↩, Code) – im Modell `\n`.
    package static let softBreak = "\u{2028}"
    package static let attachment = "\u{FFFC}"
}
