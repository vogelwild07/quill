import Foundation
import Observation
import OSLog
import QuillModel

/// Zustand von „Schnell öffnen“ (⌘O, ADR-017): Suchbegriff, Treffer nach
/// Abschnitten und die Auswahl darin.
@MainActor
@Observable
final class QuickOpenModel {
    enum SectionKind: Hashable {
        /// Ohne Suchbegriff: zuletzt bearbeitete Seiten.
        case recent
        case pages
        case content
    }

    struct Section: Identifiable {
        let kind: SectionKind
        let hits: [SearchHit]
        var id: SectionKind { kind }
    }

    var query = ""
    private(set) var sections: [Section] = []
    /// Index in `hits` (alle Abschnitte hintereinander).
    private(set) var selection = 0
    /// Erst nach dem ersten Laden „Keine Treffer“ zeigen.
    private(set) var hasLoaded = false

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "search")

    var hits: [SearchHit] { sections.flatMap(\.hits) }

    var selectedHit: SearchHit? {
        let hits = hits
        return hits.indices.contains(selection) ? hits[selection] : nil
    }

    func moveSelection(by delta: Int) {
        let count = hits.count
        guard count > 0 else { return }
        selection = min(max(0, selection + delta), count - 1)
    }

    func select(_ index: Int) {
        guard hits.indices.contains(index) else { return }
        selection = index
    }

    /// Sucht nach `debounce` Ruhe; ohne Begriff sofort die zuletzt bearbeiteten.
    /// Läuft in `.task(id: query)`: Ein neuer Begriff bricht das alte Laden ab, und
    /// veraltete Ergebnisse werden nie angezeigt.
    func load(from store: PageStore, imageText: ImageTextIndex? = nil, debounce: Duration = .milliseconds(100)) async {
        let query = query
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty {
            try? await Task.sleep(for: debounce)
        }
        guard !Task.isCancelled else { return }
        do {
            var hits = term.isEmpty ? try await store.recentPages() : try await store.search(term)
            // Bilder nach den Treffern im Text, bis zur Grenze der Suche (ADR-034).
            if let excerpts = imageText?.excerpts(matching: term), !excerpts.isEmpty {
                hits += try await store.imageHits(excerpts, limit: PageStore.searchLimit - hits.count)
            }
            guard !Task.isCancelled, query == self.query else { return }
            sections = Self.sections(hits, isSearching: !term.isEmpty)
            selection = 0
            hasLoaded = true
        } catch {
            Self.logger.error("Suche fehlgeschlagen: \(error, privacy: .public)")
        }
    }

    static func sections(_ hits: [SearchHit], isSearching: Bool) -> [Section] {
        guard isSearching else {
            return hits.isEmpty ? [] : [Section(kind: .recent, hits: hits)]
        }
        let pages = hits.filter { $0.kind == .page }
        let content = hits.filter { $0.kind != .page }
        return [Section(kind: .pages, hits: pages), Section(kind: .content, hits: content)].filter { !$0.hits.isEmpty }
    }
}
