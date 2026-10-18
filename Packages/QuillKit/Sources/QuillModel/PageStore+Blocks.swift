import Foundation
import SwiftData

/// Inhalt eines Blocks als `Sendable`-Werttyp für die Schnittstelle von `PageStore`.
public struct BlockSnapshot: Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Rohwert von `BlockKind`; unbekannte Werte späterer Versionen bleiben erhalten.
    public var kindRaw: String
    public var text: String
    public var richText: Data?
    public var indent: Int
    public var isChecked: Bool
    public var codeLanguage: String?

    public init(
        id: UUID,
        kindRaw: String = BlockKind.paragraph.rawValue,
        text: String = "",
        richText: Data? = nil,
        indent: Int = 0,
        isChecked: Bool = false,
        codeLanguage: String? = nil
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.text = text
        self.richText = richText
        self.indent = indent
        self.isChecked = isChecked
        self.codeLanguage = codeLanguage
    }
}

/// Änderungen an den Blöcken einer Seite, wie sie die `EditorPersistenceBridge` sammelt.
public struct BlockEdits: Equatable, Sendable {
    /// Neue oder geänderte Blöcke.
    public var upserts: [BlockSnapshot]
    public var deletions: [UUID]
    /// Gewünschte Reihenfolge oder `nil` = unverändert. Blöcke, die hier fehlen
    /// (z. B. aus einem anderen Fenster), behalten ihren Schlüssel.
    public var order: [UUID]?

    public init(upserts: [BlockSnapshot] = [], deletions: [UUID] = [], order: [UUID]? = nil) {
        self.upserts = upserts
        self.deletions = deletions
        self.order = order
    }

    public var isEmpty: Bool { upserts.isEmpty && deletions.isEmpty && order == nil }
}

extension PageStore {
    /// Blöcke einer Seite in Anzeigereihenfolge.
    public func blocks(of pageID: UUID) throws -> [BlockSnapshot] {
        try orderedBlocks(of: fetchPage(pageID)).map(\.snapshot)
    }

    /// Übernimmt Änderungen an Blöcken in einem Speichervorgang.
    ///
    /// `updatedAt` ändert sich nur bei Blöcken, deren Inhalt sich wirklich ändert.
    /// Für die Reihenfolge bekommen nur Blöcke einen neuen `sortKey`, die nicht schon
    /// richtig stehen (längste aufsteigende Teilfolge), wie bei Seiten (ADR-009).
    public func applyEdits(_ pageID: UUID, _ edits: BlockEdits) throws {
        guard !edits.isEmpty else { return }
        let page = try fetchPage(pageID)
        var byID: [UUID: Block] = [:]
        for block in page.blocks ?? [] where byID[block.id] == nil {
            byID[block.id] = block
        }
        var changed = false

        for id in edits.deletions {
            guard let block = byID.removeValue(forKey: id) else { continue }
            modelContext.delete(block)
            changed = true
        }

        var inserted: [Block] = []
        for snapshot in edits.upserts {
            let block: Block
            if let existing = byID[snapshot.id] {
                block = existing
            } else {
                block = Block()
                block.id = snapshot.id
                modelContext.insert(block)
                block.page = page
                byID[snapshot.id] = block
                inserted.append(block)
            }
            if block.apply(snapshot) {
                block.updatedAt = .now
                changed = true
            }
        }

        if let order = edits.order {
            changed = assignSortKeys(order: order.compactMap { byID[$0] }) || changed
        }
        // Neue Blöcke ohne Reihenfolge kommen ans Ende.
        let unplaced = inserted.filter { !FractionalIndex.isValid($0.sortKey) }
        if !unplaced.isEmpty {
            let last = byID.values.map(\.sortKey).filter(FractionalIndex.isValid).max()
            let keys = (try? FractionalIndex.keys(count: unplaced.count, between: last, and: nil))
                ?? FractionalIndex.keys(count: unplaced.count)
            for (block, key) in zip(unplaced, keys) { block.sortKey = key }
            changed = true
        }

        if changed {
            page.updatedAt = .now
            try save()
        }
    }

    // MARK: - Hilfen

    private func orderedBlocks(of page: Page) -> [Block] {
        (page.blocks ?? []).sorted { ($0.sortKey, $0.createdAt, $0.id.uuidString) < ($1.sortKey, $1.createdAt, $1.id.uuidString) }
    }

    /// Vergibt Schlüssel so, dass `order` aufsteigend ist, und ändert dabei möglichst
    /// wenige Blöcke. Gibt zurück, ob sich ein Schlüssel geändert hat.
    private func assignSortKeys(order: [Block]) -> Bool {
        let keep = Self.longestIncreasingRun(order.map(\.sortKey))
        var changed = false
        var index = 0
        while index < order.count {
            guard !keep.contains(index) else {
                index += 1
                continue
            }
            var end = index
            while end < order.count && !keep.contains(end) { end += 1 }
            let lower = index > 0 ? order[index - 1].sortKey : nil
            let upper = end < order.count ? order[end].sortKey : nil
            guard let keys = try? FractionalIndex.keys(count: end - index, between: lower, and: upper) else {
                // Sollte nicht vorkommen (behaltene Schlüssel sind gültig und aufsteigend).
                // Sicherheitsnetz: alle Blöcke der Reihenfolge neu nummerieren.
                for (block, key) in zip(order, FractionalIndex.keys(count: order.count)) {
                    block.sortKey = key
                    block.updatedAt = .now
                }
                return true
            }
            for (block, key) in zip(order[index..<end], keys) {
                block.sortKey = key
                block.updatedAt = .now
            }
            changed = true
            index = end
        }
        return changed
    }

    /// Indizes einer längsten streng aufsteigenden Teilfolge gültiger Schlüssel (O(n log n)).
    static func longestIncreasingRun(_ keys: [String]) -> Set<Int> {
        var tails: [Int] = []
        var previous = [Int](repeating: -1, count: keys.count)
        for (index, key) in keys.enumerated() where FractionalIndex.isValid(key) {
            var low = 0
            var high = tails.count
            while low < high {
                let mid = (low + high) / 2
                if keys[tails[mid]] < key { low = mid + 1 } else { high = mid }
            }
            previous[index] = low > 0 ? tails[low - 1] : -1
            if low == tails.count { tails.append(index) } else { tails[low] = index }
        }
        var result = Set<Int>()
        var cursor = tails.last ?? -1
        while cursor >= 0 {
            result.insert(cursor)
            cursor = previous[cursor]
        }
        return result
    }
}

extension Block {
    var snapshot: BlockSnapshot {
        BlockSnapshot(
            id: id, kindRaw: kindRaw, text: text, richText: richText,
            indent: indent, isChecked: isChecked, codeLanguage: codeLanguage
        )
    }

    /// Übernimmt den Inhalt; `true`, wenn sich etwas geändert hat.
    func apply(_ snapshot: BlockSnapshot) -> Bool {
        guard self.snapshot != snapshot else { return false }
        kindRaw = snapshot.kindRaw
        text = snapshot.text
        richText = snapshot.richText
        indent = snapshot.indent
        isChecked = snapshot.isChecked
        codeLanguage = snapshot.codeLanguage
        return true
    }
}
