import Foundation
import QuillModel

/// Was die Kurzbefehle mit dem Store tun (15.1, ADR-033).
public struct PageIntentActions: Sendable {
    public struct PageReference: Equatable, Sendable {
        public let id: UUID
        /// Titel wie gespeichert, leer bei „Ohne Titel“.
        public let title: String
    }

    public enum Failure: Error, Equatable {
        /// Seite gelöscht oder im Papierkorb.
        case pageMissing
        /// Nichts zum Anhängen.
        case emptyText
    }

    /// Vorschläge für die Auswahl einer Seite, höchstens so viele.
    static let suggestionLimit = 10

    let store: PageStore

    public init(store: PageStore) {
        self.store = store
    }

    /// Neue Seite am Ende der obersten Ebene, jede Zeile des Texts ein Absatz.
    public func createPage(title: String?, text: String?) async throws -> PageReference {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let id = try await store.createPage(title: title)
        let blocks = Self.blocks(for: text ?? "", continuing: nil)
        if !blocks.isEmpty {
            try await store.applyEdits(id, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        }
        return PageReference(id: id, title: title)
    }

    /// Hängt jede Zeile als Block an, vor leere Blöcke am Ende. Endet die Seite mit einer
    /// Liste (To-do, Aufzählung, Nummerierung), setzen die Blöcke sie fort.
    /// Liefert die Zahl der neuen Blöcke.
    @discardableResult
    public func append(_ text: String, to pageID: UUID) async throws -> Int {
        guard try await store.activeTitles(of: [pageID])[pageID] != nil else { throw Failure.pageMissing }
        let existing = try await store.blocks(of: pageID)
        let trailingEmpty = existing.reversed().prefix { Self.isEmptyText($0) }.count
        let kept = existing.dropLast(trailingEmpty)
        let blocks = Self.blocks(for: text, continuing: kept.last ?? existing.last)
        guard !blocks.isEmpty else { throw Failure.emptyText }
        let order = kept.map(\.id) + blocks.map(\.id) + existing.suffix(trailingEmpty).map(\.id)
        try await store.applyEdits(pageID, BlockEdits(upserts: blocks, order: order))
        return blocks.count
    }

    /// Seiten in der Reihenfolge der Kennungen, ohne fehlende.
    public func pages(_ ids: [UUID]) async throws -> [PageReference] {
        let titles = try await store.activeTitles(of: ids)
        return ids.compactMap { id in titles[id].map { PageReference(id: id, title: $0) } }
    }

    /// Seiten, deren Titel den Begriff enthält, in der Reihenfolge der Suche.
    public func pages(matching term: String) async throws -> [PageReference] {
        try await store.search(term).compactMap { hit in
            guard case .page = hit.kind else { return nil }
            return PageReference(id: hit.pageID, title: hit.title)
        }
    }

    /// Zuletzt bearbeitete Seiten.
    public func suggestedPages() async throws -> [PageReference] {
        try await store.recentPages(limit: Self.suggestionLimit).map { PageReference(id: $0.pageID, title: $0.title) }
    }

    /// Ein Block je nicht leerer Zeile; Objektzeichen (U+FFFC) gehören nur zu Bildern.
    static func blocks(for text: String, continuing last: BlockSnapshot?) -> [BlockSnapshot] {
        let listKinds: Set<BlockKind> = [.todo, .bulleted, .numbered]
        let continued = last.flatMap { BlockKind(rawValue: $0.kindRaw) }.flatMap { listKinds.contains($0) ? $0 : nil }
        var properties = BlockProperties()
        if continued != nil, let last { properties.indent = last.properties.indent }
        return text.replacingOccurrences(of: "\u{FFFC}", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { BlockSnapshot(id: UUID(), kindRaw: (continued ?? .paragraph).rawValue, text: $0, properties: properties) }
    }

    /// Textblock ohne Text; Bilder und Trenner zählen nie als leer.
    private static func isEmptyText(_ block: BlockSnapshot) -> Bool {
        guard block.text.isEmpty, let kind = BlockKind(rawValue: block.kindRaw) else { return false }
        switch kind {
        case .divider, .image: return false
        case .paragraph, .heading1, .heading2, .heading3, .bulleted, .numbered, .todo, .quote, .code: return true
        }
    }
}
