import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Eine Seite im Spotlight-Index (15.2, ADR-033).
struct SpotlightEntry: Equatable, Sendable {
    let pageID: UUID
    /// Wie gespeichert, leer bei „Ohne Titel“.
    let title: String
    let text: String
    let modified: Date
}

/// Index, in den Quill schreibt: der des Macs oder ein Ersatz für Test-Stores und Tests.
protocol SpotlightIndex: Sendable {
    /// Ersetzt alle Einträge von Quill.
    func replaceAll(with entries: [SpotlightEntry]) async throws
    /// Legt Einträge an oder ersetzt sie.
    func update(_ entries: [SpotlightEntry]) async throws
    func delete(_ pageIDs: [UUID]) async throws
    func deleteAll() async throws
}

/// Spotlight-Index des Macs, nur für den echten Store.
struct SystemSpotlightIndex: SpotlightIndex {
    static let domain = "io.github.vogelwild07.quill.pages"

    func replaceAll(with entries: [SpotlightEntry]) async throws {
        try await deleteAll()
        try await update(entries)
    }

    func update(_ entries: [SpotlightEntry]) async throws {
        guard !entries.isEmpty else { return }
        let items = entries.map { entry in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = PageLabel.title(entry.title)
            attributes.textContent = entry.text
            attributes.contentModificationDate = entry.modified
            return CSSearchableItem(uniqueIdentifier: entry.pageID.uuidString, domainIdentifier: Self.domain, attributeSet: attributes)
        }
        try await CSSearchableIndex.default().indexSearchableItems(items)
    }

    func delete(_ pageIDs: [UUID]) async throws {
        guard !pageIDs.isEmpty else { return }
        try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: pageIDs.map(\.uuidString))
    }

    func deleteAll() async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domain])
    }
}

/// Ersatz im Speicher: Test-Stores schreiben nie in den Index des Macs, denn Debug-Builds
/// haben dieselbe Kennung wie die echte App.
actor MemorySpotlightIndex: SpotlightIndex {
    private(set) var entries: [UUID: SpotlightEntry] = [:]
    /// Wie oft alles ersetzt wurde.
    private(set) var rebuilds = 0

    func replaceAll(with entries: [SpotlightEntry]) {
        rebuilds += 1
        self.entries = Dictionary(uniqueKeysWithValues: entries.map { ($0.pageID, $0) })
    }

    func update(_ entries: [SpotlightEntry]) {
        for entry in entries { self.entries[entry.pageID] = entry }
    }

    func delete(_ pageIDs: [UUID]) {
        for id in pageIDs { entries[id] = nil }
    }

    func deleteAll() {
        entries = [:]
    }
}
