import Foundation
import QuillAI
import QuillModel

/// Beantwortet eine Frage aus den Notizen (16.4, ADR-032). Die Quellen findet die
/// vorhandene Suche; ans Modell gehen nur diese Seiten, höchstens `textLimit` Zeichen.
struct NoteAnswerer {
    /// Suchbegriffe aus der Frage, höchstens so viele.
    static let maxTerms = 5
    /// Seiten, die ans Modell gehen.
    static let maxSources = 5
    /// Text aller Quellen zusammen: wie ein Stück beim Zusammenfassen.
    static let textLimit = PageSummarizer.chunkLimit
    /// Wörter der Frage, nach denen gesucht wird, wenn die Begriffe des Modells nichts finden.
    static let minWordLength = 4

    /// Die Suche findet Teile von Wörtern, nicht ganze Zusammensetzungen: „Zahnarzttermin“
    /// fände „Zahnarzt am Montag“ nicht, deshalb auch die Teile.
    static let termInstructions = """
        Du suchst in Notizen. Gib bis zu fünf kurze Suchbegriffe zurück, die in einer Notiz zu \
        dieser Frage stehen könnten: je ein einzelnes Wort in der Sprache der Frage, ohne \
        Füllwörter. Zerlege zusammengesetzte Wörter und nenne auch ihre Teile.
        """

    /// Mit dem echten Modell verglichen: Ein fester Satz für „nichts gefunden“ kam auch,
    /// wenn die Antwort in den Notizen stand; ohne die Bedingung erfand es Antworten.
    static let answerInstructions = """
        Du beantwortest Fragen zu den Notizen des Nutzers. Lies die Notizen unten und antworte \
        kurz in der Sprache der Frage, gestützt nur auf sie. Wenn keine Notiz zur Frage passt, \
        sag, dass du dazu nichts gefunden hast. Erfinde nichts dazu.
        """

    struct Source: Identifiable, Equatable {
        let pageID: UUID
        let title: String
        var id: UUID { pageID }
    }

    struct Answer: Equatable {
        let text: String
        let sources: [Source]
    }

    enum Failure: Error, Equatable {
        /// Die Frage ist leer.
        case emptyQuestion
        /// Keine Seite passt zur Frage; das Modell wurde nicht gefragt.
        case noSources
    }

    let model: any TextModel
    let store: PageStore

    func answer(_ question: String) async throws -> Answer {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { throw Failure.emptyQuestion }
        let modelTerms = Self.cleanedTerms(try await model.list(instructions: Self.termInstructions, prompt: question))
        var terms = modelTerms
        var pages = try await sources(for: terms)
        if pages.isEmpty {
            terms = Self.words(of: question)
            pages = try await sources(for: terms)
        }
        guard !pages.isEmpty else { throw Failure.noSources }
        try Task.checkCancellation()

        var notes: [String] = []
        let share = Self.textLimit / pages.count
        for (index, page) in pages.enumerated() {
            let text = PageSummarizer.plainText(try await store.blocks(of: page.pageID))
            notes.append("[\(index + 1)] \(page.title)\n\(Self.excerpt(text, around: terms, limit: share))")
        }
        let prompt = "Frage: \(question)\n\nNotizen:\n\n" + notes.joined(separator: "\n\n")
        let text = try await model.respond(instructions: Self.answerInstructions, prompt: prompt)
        return Answer(text: text.trimmingCharacters(in: .whitespacesAndNewlines), sources: pages)
    }

    /// Seiten mit den meisten Begriffen zuerst, bei Gleichstand in der Reihenfolge der Suche.
    private func sources(for terms: [String]) async throws -> [Source] {
        var order: [UUID] = []
        var counts: [UUID: Int] = [:]
        var titles: [UUID: String] = [:]
        for term in terms {
            try Task.checkCancellation()
            // Je Begriff zählt eine Seite einmal, auch mit Titel- und Inhaltstreffer.
            var counted = Set<UUID>()
            for hit in try await store.search(term) where counted.insert(hit.pageID).inserted {
                if counts[hit.pageID] == nil {
                    order.append(hit.pageID)
                    titles[hit.pageID] = hit.title
                }
                counts[hit.pageID, default: 0] += 1
            }
        }
        return order.enumerated()
            .sorted { (counts[$0.element] ?? 0, -$0.offset) > (counts[$1.element] ?? 0, -$1.offset) }
            .prefix(Self.maxSources)
            .map { Source(pageID: $0.element, title: titles[$0.element] ?? "") }
    }

    /// Ohne leere und doppelte Begriffe, ohne Groß/klein-Doppel, höchstens `maxTerms`.
    static func cleanedTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for term in terms {
            let term = term.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !term.isEmpty, seen.insert(term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)).inserted else { continue }
            result.append(term)
            if result.count == maxTerms { break }
        }
        return result
    }

    /// Wörter der Frage ab `minWordLength` Buchstaben.
    static func words(of question: String) -> [String] {
        cleanedTerms(
            question.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count >= minWordLength }
        )
    }

    /// Der ganze Text, wenn er passt, sonst `limit` Zeichen um die erste Fundstelle.
    static func excerpt(_ text: String, around terms: [String], limit: Int) -> String {
        guard text.count > limit else { return text }
        let first = terms
            .compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive])?.lowerBound }
            .min() ?? text.startIndex
        let offset = text.distance(from: text.startIndex, to: first)
        let start = max(0, min(offset - limit / 4, text.count - limit))
        let from = text.index(text.startIndex, offsetBy: start)
        return String(text[from...].prefix(limit))
    }
}
