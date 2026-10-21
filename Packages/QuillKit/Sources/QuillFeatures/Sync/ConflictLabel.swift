import Foundation
import QuillModel
import QuillSync

/// Texte zur Wahl bei Konflikten (11.6): Feld und Wert in Worten statt Rohwerten.
enum ConflictLabel {
    /// Was strittig ist, z. B. „Blockart“ oder „Titel“.
    static func field(_ conflict: PageConflict) -> String {
        switch conflict.conflict.field {
        case "kind": String(localized: "Blockart", bundle: .module)
        case "indent": String(localized: "Einzug", bundle: .module)
        case "checked": String(localized: "Erledigt", bundle: .module)
        case "lang": String(localized: "Sprache", bundle: .module)
        case "asset": String(localized: "Bild", bundle: .module)
        case "title": String(localized: "Titel", bundle: .module)
        case "icon": String(localized: "Symbol", bundle: .module)
        case "parent": String(localized: "Ort", bundle: .module)
        case nil:
            conflict.isPageField
                ? String(localized: "Ganze Seite", bundle: .module)
                : String(localized: "Ganzer Block", bundle: .module)
        default: conflict.conflict.field ?? ""
        }
    }

    /// Eine Fassung in Worten. `pageTitle` nennt die Elternseite beim Ort.
    static func value(_ version: ConflictVersion, in conflict: PageConflict, pageTitle: (UUID) -> String?) -> String {
        let value = version.value
        switch conflict.conflict.field {
        case "kind":
            return BlockKind(rawValue: value).map(kindName) ?? value
        case "indent":
            // Text statt Zahl: Eine Stufe braucht keine Pluralform.
            return String(localized: "Stufe \(value)", bundle: .module)
        case "checked":
            return value == "true"
                ? String(localized: "erledigt", bundle: .module)
                : String(localized: "offen", bundle: .module)
        case "lang":
            return value.isEmpty ? String(localized: "keine", bundle: .module) : value
        case "asset":
            return String(localized: "Bild \(String(value.prefix(4)))", bundle: .module)
        case "title":
            return PageLabel.title(value)
        case "parent":
            return UUID(uuidString: value).flatMap(pageTitle).map(PageLabel.title)
                ?? String(localized: "Oberste Ebene", bundle: .module)
        case nil:
            let summary = (version.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if conflict.isPageField { return PageLabel.title(summary) }
            return summary.isEmpty
                ? String(localized: "Leerer Block", bundle: .module)
                : String(localized: "„\(String(summary.prefix(60)))“", bundle: .module)
        default:
            return value
        }
    }

    static func kindName(_ kind: BlockKind) -> String {
        switch kind {
        case .paragraph: String(localized: "Text", bundle: .module)
        case .heading1: String(localized: "Überschrift 1", bundle: .module)
        case .heading2: String(localized: "Überschrift 2", bundle: .module)
        case .heading3: String(localized: "Überschrift 3", bundle: .module)
        case .bulleted: String(localized: "Aufzählung", bundle: .module)
        case .numbered: String(localized: "Nummerierte Liste", bundle: .module)
        case .todo: String(localized: "To-do", bundle: .module)
        case .quote: String(localized: "Zitat", bundle: .module)
        case .code: String(localized: "Code", bundle: .module)
        case .divider: String(localized: "Trennlinie", bundle: .module)
        case .image: String(localized: "Bild", bundle: .module)
        }
    }
}
