#if canImport(AppKit)
import AppKit
import QuillEditorCore
import QuillModel

extension NSPasteboard.PasteboardType {
    /// Quill-Blöcke als JSON mit Version (`BlockClipboard`).
    static let quillBlocks = NSPasteboard.PasteboardType("io.github.vogelwild07.quill.blocks")
    static let markdown = NSPasteboard.PasteboardType("net.daringfireball.markdown")
    /// Interner Ziehvorgang: IDs der gezogenen Blöcke.
    static let quillBlockDrag = NSPasteboard.PasteboardType("io.github.vogelwild07.quill.block-drag")
}

/// Zwischenablage: Kopieren über Blockgrenzen in vier Formaten, verlustfreies Einsetzen.
extension BlockEditorController {
    /// Blöcke der Auswahl; Rand-Blöcke auf den ausgewählten Text gekürzt.
    /// Eine Auswahl innerhalb eines Textblocks ergibt einen Absatz ohne Blockart:
    /// Er wird beim Einsetzen in den Text eingefügt statt als eigener Block. Ein
    /// ausgewählter atomarer Block (Bild, Trenner) wird als ganzer Block kopiert.
    private func selectedBlocks() -> (blocks: [EditorBlock], isInline: Bool)? {
        let selection = textView.selectedRange()
        guard selection.length > 0 else { return nil }
        let start = position(atCharacter: selection.location)
        var end = position(atCharacter: NSMaxRange(selection))
        if start.block == end.block {
            let block = document[start.block]
            if block.kind.isAtomic { return ([block], false) }
            var inline = EditorBlock()
            inline.content = block.content.split(at: end.offset).0.split(at: start.offset).1
            return ([inline], true)
        }
        if end.offset == 0 && NSMaxRange(selection) == paragraphStarts[end.block] {
            end = BlockPosition(block: end.block - 1, offset: BlockRenderer.displayLength(of: document[end.block - 1]))
        }
        var blocks = Array(document.blocks[start.block...end.block])
        if !blocks[0].kind.isAtomic {
            blocks[0].content = blocks[0].content.split(at: start.offset).1
        }
        let lastIndex = blocks.count - 1
        if !blocks[lastIndex].kind.isAtomic {
            let trimmedEnd = lastIndex == 0 ? end.offset - start.offset : end.offset
            blocks[lastIndex].content = blocks[lastIndex].content.split(at: trimmedEnd).0
        }
        return (blocks, false)
    }

    /// Schreibt Klartext, Markdown, RTF und Quill-Blöcke (bei einem einzelnen Bild
    /// auch PNG). `false` = keine Auswahl; dann übernimmt die Text-View.
    func copySelection(to pasteboard: NSPasteboard) -> Bool {
        guard let (blocks, isInline) = selectedBlocks() else { return false }
        let slice = EditorDocument(blocks: blocks)
        let markdown = isInline
            ? MarkdownSerializer.inlineMarkdown(blocks[0].content)
            : MarkdownSerializer.markdown(for: slice, blocks: 0..<slice.count)
        let plain = MarkdownSerializer.plainText(for: blocks)

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(plain, forType: .string)
        item.setString(markdown, forType: .markdown)
        if let data = BlockClipboard.encode(blocks) { item.setData(data, forType: .quillBlocks) }
        if let storage = textView.textStorage {
            let rich = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: textView.selectedRange()))
            rich.mutableString.replaceOccurrences(of: StorageCharacter.softBreak, with: "\n", options: [], range: NSRange(location: 0, length: rich.length))
            if let rtf = rich.rtf(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]) {
                item.setData(rtf, forType: .rtf)
            }
        }
        // Ein einzelnes Bild auch als PNG für andere Apps (Anzeigegröße aus dem Cache).
        if blocks.count == 1, blocks[0].kind == .image, let id = blocks[0].assetID,
           let image = EditorImageCache.shared.entry(for: id)?.image,
           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            item.setData(png, forType: .png)
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

    /// Fügt Quill-Blöcke verlustfrei ein, sonst Klartext (keine fremden Formate, auch
    /// keine Quill-Blöcke einer anderen Version).
    func paste(from pasteboard: NSPasteboard) -> Bool {
        let selection = textView.selectedRange()
        if let data = pasteboard.data(forType: .quillBlocks),
           let blocks = BlockClipboard.decode(data) {
            guard blocks.contains(where: { $0.kind == .image }) else {
                insertPastedBlocks(blocks, over: selection)
                return true
            }
            // Bilder bekommen erst eigene Assets; eingesetzt wird an der Auswahl von
            // dann, falls inzwischen weitergetippt wurde.
            Task {
                let copies = await withDuplicatedAssets(blocks)
                insertPastedBlocks(copies, over: textView.selectedRange())
            }
            return true
        }
        let images = Self.imageSources(from: pasteboard)
        if !images.isEmpty {
            insertImages(images, from: position(atCharacter: selection.location), to: position(atCharacter: NSMaxRange(selection)))
            return true
        }
        if let string = pasteboard.string(forType: .string) {
            textView.insertText(string, replacementRange: selection)
            return true
        }
        return false
    }

    /// Quill-Blöcke über die Auswahl einsetzen, mit neuen IDs. Ein einzelner Absatz
    /// wird in den Text eingefügt und behält seine Formatierung.
    private func insertPastedBlocks(_ blocks: [EditorBlock], over selection: NSRange) {
        guard !blocks.isEmpty else { return }
        var newDocument = document
        let start = position(atCharacter: min(selection.location, paragraphStarts[document.count] - 1))
        let end = position(atCharacter: NSMaxRange(selection))
        if blocks.count == 1, blocks[0].kind == .paragraph {
            let cursor = newDocument.insertInline(blocks[0].content, from: start, to: end)
            apply(newDocument, cursor: cursor, actionName: UndoAction.paste)
            return
        }
        var caret = start
        if selection.length > 0 {
            caret = newDocument.replace(from: start, to: end, with: "")
        }
        var cursor = newDocument.insertBlocks(blocks.map { $0.withNewID() }, at: caret)
        if newDocument.ensureEditableEnd(), cursor.block == newDocument.count - 2 {
            cursor = BlockPosition(block: cursor.block + 1, offset: 0)
        }
        apply(newDocument, cursor: cursor, actionName: UndoAction.paste)
    }
}
#endif
