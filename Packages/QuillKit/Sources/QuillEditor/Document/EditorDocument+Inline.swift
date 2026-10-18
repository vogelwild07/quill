import Foundation

/// Inline-Formatierung über einen Bereich, auch über Blockgrenzen.
/// Code-Blöcke und atomare Blöcke werden übersprungen.
extension EditorDocument {
    /// Formatierbare Teilbereiche je Block zwischen zwei Positionen.
    private func formattableRanges(from start: BlockPosition, to end: BlockPosition) -> [(block: Int, range: Range<Int>)] {
        (start.block...end.block).compactMap { index in
            let block = blocks[index]
            guard block.kind.allowsInlineMarks else { return nil }
            let lower = index == start.block ? start.offset : 0
            let upper = index == end.block ? end.offset : block.length
            return lower < upper ? (index, lower..<upper) : nil
        }
    }

    /// `true`, wenn jedes formatierbare Zeichen im Bereich die Mark trägt.
    /// Ohne formatierbare Zeichen `false`.
    public func hasMark(_ mark: InlineMark, from start: BlockPosition, to end: BlockPosition) -> Bool {
        let ranges = formattableRanges(from: start, to: end)
        return !ranges.isEmpty && ranges.allSatisfy { blocks[$0.block].content.hasMark(mark, in: $0.range) }
    }

    /// Schaltet eine Mark wie in Pages um: Tragen alle Zeichen sie schon, wird sie
    /// entfernt, sonst überall gesetzt. Gibt `false` zurück, wenn nichts formatierbar ist.
    @discardableResult
    public mutating func toggleMark(_ mark: InlineMark, from start: BlockPosition, to end: BlockPosition) -> Bool {
        let ranges = formattableRanges(from: start, to: end)
        guard !ranges.isEmpty else { return false }
        let isOn = !hasMark(mark, from: start, to: end)
        for (index, range) in ranges {
            blocks[index].content.setMark(mark, isOn, in: range)
        }
        return true
    }

    /// Setzt oder entfernt (`nil`) einen Link im Bereich.
    @discardableResult
    public mutating func setLink(_ link: String?, from start: BlockPosition, to end: BlockPosition) -> Bool {
        let ranges = formattableRanges(from: start, to: end)
        guard !ranges.isEmpty else { return false }
        for (index, range) in ranges {
            blocks[index].content.setLink(link, in: range)
        }
        return true
    }

    /// Fügt formatierten Text innerhalb eines Blocks ein (Einsetzen eines Teilblocks).
    /// Ersetzt vorher den Bereich `start`…`end`. Gibt die Position hinter dem Text zurück.
    @discardableResult
    public mutating func insertInline(_ inline: InlineText, from start: BlockPosition, to end: BlockPosition) -> BlockPosition {
        var cursor = start == end ? start : replace(from: start, to: end, with: "")
        let block = blocks[cursor.block]
        guard !block.kind.isAtomic else {
            // Neben einem Trenner: eigener Absatz dahinter.
            var paragraph = EditorBlock()
            paragraph.content = inline
            insertBlock(paragraph, at: cursor.block + 1)
            return BlockPosition(block: cursor.block + 1, offset: inline.length)
        }
        let (head, tail) = block.content.split(at: cursor.offset)
        blocks[cursor.block].content = head + inline + tail
        cursor.offset += inline.length
        return cursor
    }
}
