import Foundation
import SwiftData

/// Treffer von „Schnell öffnen“ (ADR-017).
public struct SearchHit: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// Titel passt (oder zuletzt bearbeitet ohne Suchbegriff).
        case page
        /// Text in einem Block passt; `match` ist der UTF-16-Bereich in dessen Text.
        case content(blockID: UUID, match: NSRange)
    }

    public let pageID: UUID
    public let kind: Kind
    public let title: String
    public let icon: String?
    /// Titel der Elternseiten von oben nach unten.
    public let path: [String]
    /// Ausschnitt um die Fundstelle (nur bei Inhaltstreffern).
    public let excerpt: String?

    public var id: String {
        switch kind {
        case .page: "page-\(pageID)"
        case .content(let blockID, _): "content-\(blockID)"
        }
    }
}

/// Seite im Papierkorb, wie die Liste sie zeigt.
public struct TrashedPage: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let title: String
    public let icon: String?
    public let path: [String]
    public let trashedAt: Date
    /// Erste Worte des Inhalts (`TextSnippet.preview`).
    public let preview: String

    /// Liest Titel, Pfad und Vorschau aus der Seite (auch für `@Query` in der UI).
    public init(_ page: Page) {
        let texts = (page.blocks ?? []).sorted { $0.sortKey < $1.sortKey }.map(\.text)
        id = page.id
        title = page.title
        icon = page.icon
        path = page.ancestorTitles
        trashedAt = page.trashedAt ?? .now
        preview = TextSnippet.preview(of: texts)
    }
}

extension Page {
    /// Titel der Elternseiten von oben nach unten.
    public var ancestorTitles: [String] {
        var titles: [String] = []
        var ancestor = parent
        while let current = ancestor {
            titles.insert(current.title, at: 0)
            ancestor = current.parent
        }
        return titles
    }
}

/// Favoriten, Papierkorb und Suche.
extension PageStore {
    // MARK: Favoriten

    /// Neue Favoriten kommen ans Ende. Die Reihenfolge (`favoriteSortKey`) bleibt
    /// beim Entfernen erhalten, damit Undo den alten Platz findet.
    public func setFavorite(_ pageID: UUID, _ isFavorite: Bool) throws {
        let page = try fetchPage(pageID)
        guard page.isFavorite != isFavorite else { return }
        if isFavorite {
            page.favoriteSortKey = try favoriteKey(at: .last, excluding: page)
        }
        page.isFavorite = isFavorite
        page.updatedAt = .now
        try save()
    }

    /// Verschiebt einen Favoriten innerhalb der Favoriten.
    public func moveFavorite(_ pageID: UUID, at position: SiblingPosition) throws {
        let page = try fetchPage(pageID)
        guard page.isFavorite else { return }
        page.favoriteSortKey = try favoriteKey(at: position, excluding: page)
        page.updatedAt = .now
        try save()
    }

    /// Favoriten in Anzeigereihenfolge, inklusive Papierkorb (wie Geschwister, ADR-009).
    private func favorites(excluding page: Page) throws -> [Page] {
        try modelContext.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.isFavorite }))
            .filter { $0.id != page.id }
            .sorted { ($0.favoriteSortKey ?? "", $0.createdAt, $0.id.uuidString) < ($1.favoriteSortKey ?? "", $1.createdAt, $1.id.uuidString) }
    }

    private func favoriteKey(at position: SiblingPosition, excluding page: Page) throws -> String {
        try fractionalKey(at: position, among: try favorites(excluding: page), key: \.favoriteSortKey) { $0.favoriteSortKey = $1 }
    }

    // MARK: Papierkorb

    /// Seiten mit eigenem Papierkorb-Datum, neueste zuerst.
    public func trashedPages() throws -> [TrashedPage] {
        try modelContext.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.trashedAt != nil }))
            .sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
            .map(TrashedPage.init)
    }

    /// Löscht eine Seite aus dem Papierkorb samt Unterseiten, Blöcken und Bildern.
    /// Nicht rückgängig zu machen; die UI fragt vorher.
    public func deletePermanently(_ pageID: UUID) throws {
        let page = try fetchPage(pageID)
        guard isInTrash(page) else { throw PageStoreError.notInTrash(pageID) }
        modelContext.delete(page)
        try save()
    }

    /// Leert den Papierkorb: alles oder nur Seiten, die länger als `age` darin liegen
    /// (Auto-Leeren nach 30 Tagen). Unterseiten gehen mit ihrer Elternseite; eine
    /// Unterseite mit eigenem, älterem Datum geht auch allein. Gibt die Zahl der
    /// gelöschten Einträge zurück.
    @discardableResult
    public func emptyTrash(olderThan age: TimeInterval? = nil, now: Date = .now) throws -> Int {
        let roots = try trashRoots(olderThan: age, now: now)
        for page in roots { modelContext.delete(page) }
        try save()
        return roots.count
    }

    /// Wie viele Einträge `emptyTrash(olderThan:now:)` löschen würde.
    public func trashCount(olderThan age: TimeInterval? = nil, now: Date = .now) throws -> Int {
        try trashRoots(olderThan: age, now: now).count
    }

    private func trashRoots(olderThan age: TimeInterval?, now: Date) throws -> [Page] {
        let cutoff = age.map { now.addingTimeInterval(-$0) } ?? .distantFuture
        let due = try modelContext.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.trashedAt != nil }))
            .filter { ($0.trashedAt ?? .distantFuture) <= cutoff }
        let dueIDs = Set(due.map(\.id))
        // Nur die obersten löschen; Unterseiten folgen per Cascade.
        return due.filter { page in
            var ancestor = page.parent
            while let current = ancestor {
                if dueIDs.contains(current.id) { return false }
                ancestor = current.parent
            }
            return true
        }
    }

    // MARK: Suche

    /// Sucht nach Titel und Inhalt, ohne Groß/klein und Akzente. Seiten im Papierkorb
    /// (auch logisch über eine Elternseite) zählen nicht. Titeltreffer zuerst: Titel
    /// beginnt mit dem Begriff, dann ein Wort darin, dann irgendwo; bei Gleichstand
    /// zuletzt bearbeitet. Danach ein Inhaltstreffer je Seite (erster Block).
    public func search(_ query: String, limit: Int = 50) throws -> [SearchHit] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let folded = Self.fold(term)

        let titled = try modelContext.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.title.localizedStandardContains(term) }))
            .filter { !isInTrash($0) }
            .map { (page: $0, rank: Self.titleRank(Self.fold($0.title), folded)) }
            .sorted { ($0.rank, $1.page.updatedAt) < ($1.rank, $0.page.updatedAt) }
        var hits = titled.prefix(limit).map { pageHit($0.page) }
        let titledIDs = Set(titled.map(\.page.id))

        // Ein Treffer je Seite: der erste passende Block. Die Seite wird mitgeladen,
        // vom Block nur, was gebraucht wird.
        var descriptor = FetchDescriptor<Block>(predicate: #Predicate { $0.text.localizedStandardContains(term) })
        descriptor.fetchLimit = Self.contentScanLimit
        descriptor.relationshipKeyPathsForPrefetching = [\.page]
        descriptor.propertiesToFetch = [\.text, \.sortKey]
        var best: [UUID: Block] = [:]
        for block in try modelContext.fetch(descriptor) {
            guard let page = block.page, !titledIDs.contains(page.id) else { continue }
            if let current = best[page.id], current.sortKey <= block.sortKey { continue }
            best[page.id] = block
        }
        let content = best.values
            .compactMap { block in block.page.map { (page: $0, block: block) } }
            .filter { !isInTrash($0.page) }
            .sorted { $0.page.updatedAt > $1.page.updatedAt }
            .prefix(max(0, limit - hits.count))
            .map { page, block in
                let match = (block.text as NSString).range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
                return SearchHit(
                    pageID: page.id, kind: .content(blockID: block.id, match: match), title: page.title,
                    icon: page.icon, path: path(of: page), excerpt: TextSnippet.excerpt(block.text, around: match)
                )
            }
        hits += content
        return hits
    }

    /// Zuletzt bearbeitete Seiten (ohne Papierkorb), für „Schnell öffnen“ ohne Begriff.
    public func recentPages(limit: Int = 10) throws -> [SearchHit] {
        var descriptor = FetchDescriptor<Page>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = limit * 4
        return try modelContext.fetch(descriptor)
            .filter { !isInTrash($0) }
            .prefix(limit)
            .map(pageHit)
    }

    private func pageHit(_ page: Page) -> SearchHit {
        SearchHit(pageID: page.id, kind: .page, title: page.title, icon: page.icon, path: path(of: page), excerpt: nil)
    }

    private func path(of page: Page) -> [String] {
        page.ancestorTitles
    }

    /// Höchstens so viele passende Blöcke werden gelesen; bei sehr häufigen Begriffen
    /// fehlen dann einzelne Inhaltstreffer, die Titeltreffer bleiben vollständig.
    static let contentScanLimit = 500

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// 0: Titel beginnt mit dem Begriff, 1: ein Wort beginnt damit, 2: irgendwo.
    static func titleRank(_ title: String, _ term: String) -> Int {
        if title.hasPrefix(term) { return 0 }
        let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return words.contains { $0.hasPrefix(term) } ? 1 : 2
    }
}
