import Foundation
import QuillAI
import QuillModel

/// Seiten zum selben Thema (16.5, ADR-032): Suchbegriffe des Modells aus der Seite,
/// die Seiten findet die vorhandene Suche.
struct RelatedPageFinder {
    /// Vorgeschlagene Seiten, höchstens so viele.
    static let maxPages = 5
    /// Text der Seite für die Suchbegriffe; längere Seiten mit ihrem Anfang.
    static let textLimit = PageSummarizer.chunkLimit

    /// Mit dem echten Modell verglichen: „das Thema beschreiben“ gab allgemeine Wörter,
    /// „Namen und Dinge“ Orte und Namen. Zusammensetzungen zerlegt es trotzdem nicht immer.
    static let termInstructions = """
        Du suchst Notizen zum selben Thema. Gib bis zu fünf Suchbegriffe zurück, die in einer \
        verwandten Notiz stehen könnten: die wichtigsten Namen und Dinge dieser Notiz, je ein \
        einzelnes Wort in ihrer Sprache, ohne Füllwörter. Zerlege zusammengesetzte Wörter und \
        nenne auch ihre Teile.
        """

    enum Failure: Error, Equatable {
        /// Seite ohne Titel und Text; das Modell wurde nicht gefragt.
        case empty
    }

    let model: any TextModel
    let store: PageStore

    func related(to pageID: UUID, title: String) async throws -> [TermSearch.Match] {
        let text = PageSummarizer.plainText(try await store.blocks(of: pageID))
        let prompt = [title, text]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !prompt.isEmpty else { throw Failure.empty }
        let terms = TermSearch.cleaned(
            try await model.list(instructions: Self.termInstructions, prompt: String(prompt.prefix(Self.textLimit)))
        )
        return try await TermSearch(store: store).pages(for: terms, excluding: pageID, limit: Self.maxPages)
    }
}
