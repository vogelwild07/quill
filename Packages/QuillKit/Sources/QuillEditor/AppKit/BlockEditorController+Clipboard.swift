#if canImport(AppKit)
import AppKit

extension NSPasteboard.PasteboardType {
    /// Quill-Blöcke als JSON (`[EditorBlock]`).
    static let quillBlocks = NSPasteboard.PasteboardType("de.vogel.quill.blocks")
    static let markdown = NSPasteboard.PasteboardType("net.daringfireball.markdown")
    /// Interner Ziehvorgang: IDs der gezogenen Blöcke.
    static let quillBlockDrag = NSPasteboard.PasteboardType("de.vogel.quill.block-drag")
}

/// Zwischenablage: Kopieren über Blockgrenzen in vier Formaten, verlustfreies Einsetzen.
extension BlockEditorController {
    /// Blöcke der Auswahl; Rand-Blöcke auf den ausgewählten Text gekürzt.
    private func selectedBlocks() -> [EditorBlock]? {
        let selection = textView.selectedRange()
        guard selection.length > 0 else { return nil }
        let start = position(atCharacter: selection.location)
        var end = position(atCharacter: NSMaxRange(selection))
        guard start.block != end.block else { return nil }
        if end.offset == 0 && NSMaxRange(selection) == paragraphStarts[end.block] {
            end = BlockPosition(block: end.block - 1, offset: BlockRenderer.displayLength(of: document[end.block - 1]))
        }
        var blocks = Array(document.blocks[start.block...end.block])
        if !blocks[0].kind.isAtomic {
            blocks[0].text = EditorDocument.split(blocks[0].text, at: start.offset).1
        }
        let lastIndex = blocks.count - 1
        if !blocks[lastIndex].kind.isAtomic {
            let trimmedEnd = lastIndex == 0 ? end.offset - start.offset : end.offset
            blocks[lastIndex].text = EditorDocument.split(blocks[lastIndex].text, at: trimmedEnd).0
        }
        return blocks
    }

    /// Schreibt Klartext, Markdown, RTF und Quill-Blöcke. `false` = einfache Auswahl
    /// innerhalb eines Blocks; dann übernimmt die Text-View.
    func copySelection(to pasteboard: NSPasteboard) -> Bool {
        guard let blocks = selectedBlocks() else { return false }
        let slice = EditorDocument(blocks: blocks)
        let markdown = MarkdownSerializer.markdown(for: slice, blocks: 0..<slice.count)
        let plain = MarkdownSerializer.plainText(for: blocks)

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(plain, forType: .string)
        item.setString(markdown, forType: .markdown)
        if let data = try? JSONEncoder().encode(blocks) { item.setData(data, forType: .quillBlocks) }
        if let storage = textView.textStorage {
            let rich = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: textView.selectedRange()))
            rich.mutableString.replaceOccurrences(of: StorageCharacter.softBreak, with: "\n", options: [], range: NSRange(location: 0, length: rich.length))
            if let rtf = rich.rtf(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]) {
                item.setData(rtf, forType: .rtf)
            }
        }
        pasteboard.writeObjects([item])
        return true
    }

    func cutSelection(to pasteboard: NSPasteboard) -> Bool {
        guard copySelection(to: pasteboard) else { return false }
        let selection = textView.selectedRange()
        var newDocument = document
        let cursor = newDocument.replace(from: position(atCharacter: selection.location), to: position(atCharacter: NSMaxRange(selection)), with: "")
        apply(newDocument, cursor: cursor, actionName: UndoAction.cut)
        return true
    }

    /// Fügt Quill-Blöcke verlustfrei ein, sonst Klartext (keine fremden Formate).
    func paste(from pasteboard: NSPasteboard) -> Bool {
        let selection = textView.selectedRange()
        if let data = pasteboard.data(forType: .quillBlocks),
           let blocks = try? JSONDecoder().decode([EditorBlock].self, from: data) {
            var newDocument = document
            var caret = position(atCharacter: selection.location)
            if selection.length > 0 {
                caret = newDocument.replace(from: caret, to: position(atCharacter: NSMaxRange(selection)), with: "")
            }
            let fresh = blocks.map { block -> EditorBlock in
                var copy = block
                copy.id = UUID()
                return copy
            }
            let cursor = newDocument.insertBlocks(fresh, at: caret)
            apply(newDocument, cursor: cursor, actionName: UndoAction.paste)
            return true
        }
        if let string = pasteboard.string(forType: .string) {
            textView.insertText(string, replacementRange: selection)
            return true
        }
        return false
    }
}
#endif
