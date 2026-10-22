import Foundation
import QuillAI

/// Gründe, warum das Modell nicht geantwortet hat, als Satz für Zusammenfassen und To-dos.
enum AIProblem {
    /// `fallback` für Fehler ohne eigenen Satz.
    static func message(_ error: any Error, fallback: String) -> String {
        switch error {
        case AIError.tooLong:
            String(localized: "Ein Abschnitt ist zu lang für das Sprachmodell.", bundle: .module)
        case AIError.refused:
            String(localized: "Das Sprachmodell hat diesen Text abgelehnt.", bundle: .module)
        case AIError.unsupportedLanguage:
            String(localized: "Das Sprachmodell unterstützt die Sprache dieses Textes nicht.", bundle: .module)
        case AIError.unavailable:
            String(localized: "Das Sprachmodell steht gerade nicht bereit.", bundle: .module)
        default:
            fallback
        }
    }
}
