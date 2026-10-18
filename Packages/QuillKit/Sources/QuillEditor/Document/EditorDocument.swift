import Foundation

/// Dokument eines Editors: geordnete, flache Liste von Blöcken.
///
/// Alle strukturellen Operationen (Teilen, Verbinden, Einrücken, Verschieben, …)
/// leben hier, ohne AppKit, damit sie mit Unit-Tests abgesichert sind.
/// Ein Dokument enthält immer mindestens einen Block.
public struct EditorDocument: Equatable, Sendable {
    public internal(set) var blocks: [EditorBlock]

    public static let maxIndent = 6

    public init(blocks: [EditorBlock] = []) {
        self.blocks = blocks.isEmpty ? [EditorBlock()] : blocks
    }

    public subscript(index: Int) -> EditorBlock {
        get { blocks[index] }
        set { blocks[index] = newValue }
    }

    public var count: Int { blocks.count }

    // MARK: Enter

    /// Enter an `position`. Gibt die neue Cursorposition zurück.
    @discardableResult
    public mutating func splitBlock(at position: BlockPosition) -> BlockPosition {
        let index = position.block
        let block = blocks[index]

        if block.kind.isAtomic {
            blocks.insert(EditorBlock(indent: 0), at: index + 1)
            return BlockPosition(block: index + 1, offset: 0)
        }
        if block.kind == .code {
            return insertText("\n", at: position)
        }
        // Leerer Listenpunkt oder leeres Zitat: Liste verlassen statt neuen Punkt anlegen.
        if block.text.isEmpty && (block.kind.isListItem || block.kind == .quote) {
            if block.indent > 0 {
                blocks[index].indent -= 1
            } else {
                blocks[index].kind = .paragraph
                blocks[index].isChecked = false
            }
            return position
        }
        // Enter am Anfang eines nicht leeren Blocks: leeren Block darüber einfügen,
        // der aktuelle Block behält Art und ID.
        if position.offset == 0 && !block.text.isEmpty {
            var above = EditorBlock(kind: block.kind.isListItem ? block.kind : .paragraph, indent: block.indent)
            if block.kind == .quote { above.kind = .quote }
            blocks.insert(above, at: index)
            return BlockPosition(block: index + 1, offset: 0)
        }

        let (head, tail) = block.content.split(at: position.offset)
        blocks[index].content = head
        var next = EditorBlock(
            kind: Self.continuation(of: block.kind),
            indent: block.kind.isHeading ? 0 : block.indent
        )
        next.content = tail
        blocks.insert(next, at: index + 1)
        return BlockPosition(block: index + 1, offset: 0)
    }

    private static func continuation(of kind: BlockKind) -> BlockKind {
        switch kind {
        case .bulleted, .numbered, .todo, .quote: kind
        default: .paragraph
        }
    }

    // MARK: Backspace

    /// Backspace bei Offset 0. Gibt die neue Cursorposition zurück oder `nil`,
    /// wenn nichts zu tun ist (Anfang des Dokuments).
    public mutating func deleteBackwardAtStart(of index: Int) -> BlockPosition? {
        let block = blocks[index]
        if block.kind.isAtomic {
            return deleteBlock(at: index)
        }
        if block.kind != .paragraph {
            blocks[index].kind = .paragraph
            blocks[index].isChecked = false
            blocks[index].codeLanguage = nil
            return BlockPosition(block: index, offset: 0)
        }
        if block.indent > 0 {
            blocks[index].indent -= 1
            return BlockPosition(block: index, offset: 0)
        }
        guard index > 0 else { return nil }

        let previous = blocks[index - 1]
        if previous.kind.isAtomic {
            blocks.remove(at: index - 1)
            return BlockPosition(block: index - 1, offset: 0)
        }
        let offset = previous.length
        blocks[index - 1].content = previous.content + block.content
        blocks.remove(at: index)
        return BlockPosition(block: index - 1, offset: offset)
    }

    /// Entfernt einen Block; das Dokument bleibt nie leer.
    @discardableResult
    public mutating func deleteBlock(at index: Int) -> BlockPosition {
        blocks.remove(at: index)
        if blocks.isEmpty {
            blocks = [EditorBlock()]
            return BlockPosition(block: 0, offset: 0)
        }
        let target = min(index, blocks.count - 1)
        return BlockPosition(block: target, offset: index < blocks.count ? 0 : blocks[target].length)
    }

    // MARK: Text

    /// Fügt Text ein. Zeilenumbrüche erzeugen neue Absätze, außer im Code-Block.
    @discardableResult
    public mutating func insertText(_ text: String, at position: BlockPosition) -> BlockPosition {
        replace(from: position, to: position, with: text)
    }

    /// Ersetzt den Bereich zwischen zwei Positionen (auch über Blockgrenzen) durch Text.
    /// Der erste betroffene Block behält Art und ID.
    @discardableResult
    public mutating func replace(from start: BlockPosition, to end: BlockPosition, with text: String) -> BlockPosition {
        let first = blocks[start.block]
        let last = blocks[end.block]
        let head = first.content.split(at: start.offset).0
        let tail = last.content.split(at: end.offset).1

        let keepsLineBreaks = first.kind == .code
        let lines = keepsLineBreaks ? [text] : text.components(separatedBy: "\n")

        var replacement = first
        replacement.content = head + InlineText(lines[0])
        var newBlocks = [replacement]
        for line in lines.dropFirst() {
            newBlocks.append(EditorBlock(kind: .paragraph, text: line, indent: first.indent))
        }
        let cursorOffset = newBlocks[newBlocks.count - 1].length
        newBlocks[newBlocks.count - 1].content = newBlocks[newBlocks.count - 1].content + tail

        blocks.replaceSubrange(start.block...end.block, with: newBlocks)
        return BlockPosition(block: start.block + newBlocks.count - 1, offset: cursorOffset)
    }

    /// Fügt einen Block an einem Index ein.
    public mutating func insertBlock(_ block: EditorBlock, at index: Int) {
        blocks.insert(block, at: max(0, min(index, blocks.count)))
    }

    /// Fügt Blöcke an der Cursorposition ein (Einfügen aus der Zwischenablage).
    /// Ein leerer Absatz wird ersetzt, sonst wird bei Bedarf geteilt.
    /// Gibt die Position am Ende des letzten eingefügten Blocks zurück.
    @discardableResult
    public mutating func insertBlocks(_ newBlocks: [EditorBlock], at position: BlockPosition) -> BlockPosition {
        guard !newBlocks.isEmpty else { return position }
        let index = position.block
        let block = blocks[index]
        let insertAt: Int
        if block.kind == .paragraph && block.text.isEmpty {
            blocks.remove(at: index)
            insertAt = index
        } else if position.offset == 0 && !block.kind.isAtomic {
            insertAt = index
        } else if position.offset >= block.length || block.kind.isAtomic {
            insertAt = index + 1
        } else {
            let (head, tail) = block.content.split(at: position.offset)
            blocks[index].content = head
            var rest = block
            rest.id = UUID()
            rest.content = tail
            blocks.insert(rest, at: index + 1)
            insertAt = index + 1
        }
        blocks.insert(contentsOf: newBlocks, at: insertAt)
        let last = insertAt + newBlocks.count - 1
        return BlockPosition(block: last, offset: blocks[last].length)
    }

    // MARK: Art, Einrückung, Häkchen

    public mutating func setKind(_ kind: BlockKind, at index: Int) {
        blocks[index].kind = kind
        if kind != .todo { blocks[index].isChecked = false }
        if kind != .code { blocks[index].codeLanguage = nil }
        if !kind.allowsInlineMarks { blocks[index].spans = [] }
        if kind.isAtomic {
            blocks[index].content = InlineText()
            blocks[index].indent = 0
            if index == blocks.count - 1 {
                blocks.append(EditorBlock())
            }
        }
        if kind.isHeading || kind == .code || kind == .quote {
            blocks[index].indent = 0
        }
    }

    /// Tab: höchstens eine Stufe tiefer als der vorherige Block.
    @discardableResult
    public mutating func indent(at index: Int) -> Bool {
        guard index > 0, blocks[index].kind.isIndentable else { return false }
        let limit = min(blocks[index - 1].indent + 1, Self.maxIndent)
        guard blocks[index].indent < limit else { return false }
        blocks[index].indent += 1
        return true
    }

    /// ⇧Tab.
    @discardableResult
    public mutating func outdent(at index: Int) -> Bool {
        guard blocks[index].indent > 0 else { return false }
        blocks[index].indent -= 1
        return true
    }

    public mutating func toggleChecked(at index: Int) {
        guard blocks[index].kind == .todo else { return }
        blocks[index].isChecked.toggle()
    }

    // MARK: Verschieben

    /// Verschiebt die Blöcke `indices` vor den Block, der vor dem Verschieben bei
    /// `destination` stand (`destination == count` hängt ans Ende).
    /// Gibt den neuen Indexbereich der verschobenen Blöcke zurück.
    @discardableResult
    public mutating func moveBlocks(_ indices: IndexSet, to destination: Int) -> Range<Int> {
        guard !indices.isEmpty else { return destination..<destination }
        let moving = indices.map { blocks[$0] }
        let insertAt = destination - indices.count(in: 0..<destination)
        for index in indices.reversed() {
            blocks.remove(at: index)
        }
        blocks.insert(contentsOf: moving, at: insertAt)
        let range = insertAt..<(insertAt + moving.count)

        // Einrückung relativ halten, aber nicht tiefer als erlaubt.
        let limit = insertAt > 0 ? blocks[insertAt - 1].indent + 1 : 0
        let shift = max(0, blocks[insertAt].indent - limit)
        if shift > 0 {
            for index in range {
                blocks[index].indent = max(0, blocks[index].indent - shift)
            }
        }
        return range
    }

    // MARK: Abfragen

    /// Nummer eines nummerierten Listenpunkts (1-basiert).
    public func listOrdinal(at index: Int) -> Int {
        let indent = blocks[index].indent
        var ordinal = 1
        var cursor = index - 1
        while cursor >= 0 {
            let block = blocks[cursor]
            if block.indent > indent { cursor -= 1; continue }
            guard block.indent == indent, block.kind == .numbered else { break }
            ordinal += 1
            cursor -= 1
        }
        return ordinal
    }

    // MARK: Hilfen

    /// Teilt einen String an einem UTF-16-Offset.
    public static func split(_ text: String, at offset: Int) -> (String, String) {
        let ns = text as NSString
        let clamped = max(0, min(offset, ns.length))
        return (ns.substring(to: clamped), ns.substring(from: clamped))
    }
}
