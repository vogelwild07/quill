import Foundation
import QuillModel

/// Seiten zu Suchbegriffen des Modells aus der vorhandenen Suche (16.4, 16.5, ADR-032):
/// kein eigener Index, Papierkorb nie.
struct TermSearch {
    /// Suchbegriffe, höchstens so viele.
    static let maxTerms = 5

    struct Match: Identifiable, Equatable {
        let pageID: UUID
        let title: String
        /// Begriffe, die die Seite enthält, in der Reihenfolge der Begriffe.
        let terms: [String]
        var id: UUID { pageID }
    }

    let store: PageStore

    /// Seiten mit den meisten Begriffen zuerst, bei Gleichstand in der Reihenfolge der Suche.
    func pages(for terms: [String], excluding excluded: UUID? = nil, limit: Int) async throws -> [Match] {
        var order: [UUID] = []
        var found: [UUID: [String]] = [:]
        var titles: [UUID: String] = [:]
        for term in terms {
            try Task.checkCancellation()
            // Die Suche liefert höchstens einen Treffer je Seite.
            for hit in try await store.search(term) where hit.pageID != excluded {
                if found[hit.pageID] == nil {
                    order.append(hit.pageID)
                    titles[hit.pageID] = hit.title
                }
                found[hit.pageID, default: []].append(term)
            }
        }
        let count = { (id: UUID) in found[id]?.count ?? 0 }
        return order.enumerated()
            .sorted { (count($0.element), -$0.offset) > (count($1.element), -$1.offset) }
            .prefix(limit)
            .map { Match(pageID: $0.element, title: titles[$0.element] ?? "", terms: found[$0.element] ?? []) }
    }

    /// Ohne leere und doppelte Begriffe, ohne Groß/klein-Doppel, höchstens `maxTerms`.
    static func cleaned(_ terms: [String]) -> [String] {
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
}
