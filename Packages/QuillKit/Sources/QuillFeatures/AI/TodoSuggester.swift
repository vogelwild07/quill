import Foundation
import QuillAI
import QuillModel

/// Findet Aufgaben in markierten Absätzen (16.3, ADR-032). Lange Auswahl geht in Stücken
/// an das Modell, die Listen werden aneinandergehängt.
struct TodoSuggester {
    /// Höchstens so viele Vorschläge; mehr wären keine Hilfe beim Durchsehen.
    static let maxItems = 50

    static let instructions = """
        Du findest Aufgaben in Notizen. Gib jede Aufgabe, die in der Notiz steht, als kurzen \
        Eintrag in der Sprache der Notiz zurück. Erfinde keine Aufgaben dazu; steht keine in \
        der Notiz, gib eine leere Liste zurück.
        """

    enum Failure: Error, Equatable {
        /// Die Auswahl hat keinen Text.
        case empty
        /// Das Modell hat keine Aufgabe gefunden.
        case noTasks
    }

    let model: any TextModel

    func suggest(_ blocks: [(kind: BlockKind?, text: String)]) async throws -> [String] {
        let text = PageSummarizer.plainText(blocks)
        guard !text.isEmpty else { throw Failure.empty }
        var items: [String] = []
        for part in PageSummarizer.chunks(text, limit: PageSummarizer.chunkLimit) {
            try Task.checkCancellation()
            items += try await model.list(instructions: Self.instructions, prompt: part)
        }
        let cleaned = Self.cleaned(items)
        guard !cleaned.isEmpty else { throw Failure.noTasks }
        return cleaned
    }

    /// Ohne Aufzählungszeichen, Nummern und Kästchen, ohne leere und doppelte Einträge,
    /// jeder in einer Zeile (ein To-do ist ein Block).
    static func cleaned(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            var text = item.split(whereSeparator: \.isNewline).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            // Auch doppelt, etwa „- [ ] Milch kaufen“.
            while let marker = text.firstMatch(of: /^(?:[-–•*]|\d+[.)]|\[[ xX]?\])(?:\s+|$)/) {
                text = String(text[marker.range.upperBound...])
            }
            guard !text.isEmpty, seen.insert(text).inserted else { continue }
            result.append(text)
            if result.count == maxItems { break }
        }
        return result
    }
}
