import Foundation

extension EditorDocument {
    /// Zeitreise (12.3, ADR-031): holt die Blöcke `chosen` aus dem früheren Stand `old`
    /// zurück. Gibt es einen Block noch, bekommt er seinen früheren Inhalt an seiner
    /// jetzigen Stelle. Sonst kommt er hinter den nächsten früheren Vorgänger, den es
    /// jetzt gibt, ohne Vorgänger an den Anfang; der leere Absatz einer leeren Seite
    /// wird dabei ersetzt. Gibt die IDs der zurückgeholten Blöcke zurück, in der
    /// Reihenfolge von `old`.
    @discardableResult
    public mutating func restore(_ chosen: Set<UUID>, from old: [EditorBlock]) -> [UUID] {
        var restored: [UUID] = []
        for (oldIndex, block) in old.enumerated() where chosen.contains(block.id) {
            if let index = blocks.firstIndex(where: { $0.id == block.id }) {
                blocks[index] = block
            } else if let anchor = nearestIndex(of: old[..<oldIndex].reversed()) {
                blocks.insert(block, at: anchor + 1)
            } else if blocks.count == 1, blocks[0].isPristine {
                blocks[0] = block
            } else {
                blocks.insert(block, at: 0)
            }
            restored.append(block.id)
        }
        return restored
    }

    /// Stelle des ersten Blocks aus `candidates`, den es im Dokument gibt.
    private func nearestIndex(of candidates: some Sequence<EditorBlock>) -> Int? {
        for candidate in candidates {
            if let index = blocks.firstIndex(where: { $0.id == candidate.id }) { return index }
        }
        return nil
    }
}
