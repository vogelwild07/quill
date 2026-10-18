#if canImport(AppKit)
import AppKit
import QuillModel

/// Eingabe: Abfangen von Änderungen über Blockgrenzen, Enter, Tab, Backspace,
/// Markdown-Kürzel und Slash-Menü.
/// Ein Klick auf ＋, den Escape noch zurücknehmen kann.
struct PendingInsert {
    let blockID: UUID
    /// Ein vorhandener leerer Absatz wurde genutzt: Escape leert ihn nur.
    let reusedEmptyParagraph: Bool
    /// Stand direkt nach dem Klick; nur dann liegt „Neuer Block“ oben auf dem Undo-Stapel.
    let documentAfterInsert: EditorDocument
    let selectionBefore: NSRange
}

extension BlockEditorController: NSTextViewDelegate {
    // MARK: Abfangen

    public func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        guard !isApplying, let replacement = replacementString else { return true }
        if textView.hasMarkedText() { return true }
        // Undo/Redo spielt frühere Änderungen 1:1 zurück; danach wird das Modell gelesen.
        if let undoManager = textView.undoManager, undoManager.isUndoing || undoManager.isRedoing { return true }
        lastInsertedString = replacement

        let string = textView.string as NSString
        let crossesBlocks = range.length > 0
            && string.rangeOfCharacter(from: CharacterSet(charactersIn: "\n"), options: [], range: range).location != NSNotFound
        let insertsBlocks = replacement.contains("\n") || replacement.contains("\r")
        let start = position(atCharacter: range.location)
        let touchesAtomic = document[start.block].kind.isAtomic

        guard crossesBlocks || insertsBlocks || touchesAtomic else { return true }

        var newDocument = document
        let text = replacement.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if touchesAtomic && range.length == 0 {
            guard !text.isEmpty else { return false }
            // Tippen vor/hinter einem Trenner: neuer Absatz davor bzw. dahinter.
            let index = start.offset == 0 ? start.block : start.block + 1
            newDocument.insertBlock(EditorBlock(), at: index)
            let cursor = newDocument.insertText(text, at: BlockPosition(block: index, offset: 0))
            apply(newDocument, cursor: cursor, actionName: UndoAction.typing)
            return false
        }
        guard NSMaxRange(range) < string.length else { return false }
        let end = position(atCharacter: NSMaxRange(range))
        let cursor = newDocument.replace(from: start, to: end, with: text)
        apply(newDocument, cursor: cursor, actionName: UndoAction.typing)
        return false
    }

    public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if slashMenu.isVisible, slashMenu.handle(selector) { return true }
        let selection = textView.selectedRange()
        let caret = position(atCharacter: selection.location)

        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if document[caret.block].kind == .code && selection.length == 0 {
                textView.insertLineBreak(nil)
                return true
            }
            var newDocument = document
            var cursor = caret
            if selection.length > 0 {
                cursor = newDocument.replace(from: caret, to: position(atCharacter: NSMaxRange(selection)), with: "")
            }
            cursor = newDocument.splitBlock(at: cursor)
            apply(newDocument, cursor: cursor, actionName: UndoAction.newBlock)
            return true

        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            if document[caret.block].kind == .code && selector == #selector(NSResponder.insertTab(_:)) {
                return false
            }
            let indent = selector == #selector(NSResponder.insertTab(_:))
            let last = blockIndex(atCharacter: max(selection.location, NSMaxRange(selection) - (selection.length > 0 ? 1 : 0)))
            var newDocument = document
            var changed = false
            for index in caret.block...last {
                changed = (indent ? newDocument.indent(at: index) : newDocument.outdent(at: index)) || changed
            }
            if changed {
                apply(newDocument, cursor: nil, actionName: indent ? UndoAction.indent : UndoAction.outdent)
                textView.setSelectedRange(remap(selection, from: caret.block, to: last))
            }
            return true

        case #selector(NSResponder.cancelOperation(_:)):
            return revertInsertBlockWithMenu()

        case #selector(NSResponder.moveUp(_:)):
            guard let onExitTop, isCaretOnFirstLine() else { return false }
            onExitTop()
            return true

        case #selector(NSResponder.deleteBackward(_:)):
            guard selection.length == 0 else { return false }
            if caret.offset == 0 {
                var newDocument = document
                if let cursor = newDocument.deleteBackwardAtStart(of: caret.block) {
                    apply(newDocument, cursor: cursor, actionName: UndoAction.delete)
                } else {
                    NSSound.beep()
                }
                return true
            }
            if document[caret.block].kind.isAtomic {
                var newDocument = document
                let cursor = newDocument.deleteBlock(at: caret.block)
                apply(newDocument, cursor: cursor, actionName: UndoAction.delete)
                return true
            }
            return false

        default:
            return false
        }
    }

    public func undoManager(for view: NSTextView) -> UndoManager? {
        undoManager
    }

    /// Hält die Auswahl über dieselben Blöcke, nachdem sich Einrückungen geändert haben.
    private func remap(_ selection: NSRange, from first: Int, to last: Int) -> NSRange {
        let start = paragraphStarts[first]
        let end = paragraphStarts[last + 1] - 1
        return selection.length == 0
            ? NSRange(location: min(selection.location, end), length: 0)
            : NSRange(location: start, length: end - start)
    }

    // MARK: Nach dem Tippen

    public func textDidChange(_ notification: Notification) {
        guard !isApplying else { return }
        if !syncSingleParagraph() { syncFromStorage() }

        let inserted = lastInsertedString
        lastInsertedString = nil
        guard !textView.hasMarkedText() else { return }
        let caret = position(atCharacter: textView.selectedRange().location)

        if inserted == " " || inserted == "-" {
            var newDocument = document
            if let cursor = newDocument.applyMarkdownShortcut(at: caret) {
                // Eigener Undo-Schritt: ⌘Z stellt das getippte Kürzel wieder her.
                textView.breakUndoCoalescing()
                apply(newDocument, cursor: cursor, actionName: UndoAction.markdownShortcut)
                return
            }
        }
        if inserted == "/" {
            slashMenu.openIfAllowed(slashLocation: textView.selectedRange().location - 1)
        } else if slashMenu.isVisible {
            slashMenu.update()
        }
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        // Beim Tippen kommt die Auswahl vor `textDidChange`; die Absätze sind dann noch
        // nicht abgeglichen, und `textDidChange` aktualisiert das Menü ohnehin.
        if slashMenu.isVisible, editedRange == nil { slashMenu.update() }
        // Cursor verlässt den Block nach ＋: Escape nimmt dann nichts mehr zurück.
        if let pendingInsert, editedRange == nil, !isApplying, !slashMenu.isVisible,
           document[blockIndex(atCharacter: caretLocation)].id != pendingInsert.blockID {
            self.pendingInsert = nil
        }
    }

    // MARK: Aktionen

    func toggleChecked(atCharacter location: Int) {
        let index = blockIndex(atCharacter: location)
        var newDocument = document
        newDocument.toggleChecked(at: index)
        let selection = textView.selectedRange()
        apply(newDocument, cursor: nil, actionName: UndoAction.toggleChecked)
        textView.setSelectedRange(selection)
    }

    /// Einfügen-Knopf ＋: neuer leerer Absatz unter dem Block (mit ⌥ darüber), darin
    /// „/“ mit offenem Slash-Menü. Ein leerer Absatz wird selbst genutzt. Ein Undo-Schritt.
    func insertBlockWithMenu(nearCharacter location: Int, above: Bool) {
        let index = blockIndex(atCharacter: location)
        let reused = document[index].kind == .paragraph && document[index].text.isEmpty
        var newDocument = document
        var target = index
        if !reused {
            target = above ? index : index + 1
            newDocument.insertBlock(EditorBlock(), at: target)
        }
        let cursor = newDocument.insertText("/", at: BlockPosition(block: target, offset: 0))
        let selection = textView.selectedRange()
        textView.breakUndoCoalescing()
        apply(newDocument, cursor: cursor, actionName: UndoAction.newBlock)
        textView.breakUndoCoalescing()
        window?.makeFirstResponder(textView)
        pendingInsert = PendingInsert(
            blockID: document[target].id, reusedEmptyParagraph: reused,
            documentAfterInsert: document, selectionBefore: selection
        )
        slashMenu.openIfAllowed(slashLocation: characterLocation(of: BlockPosition(block: target, offset: 0)))
    }

    /// Escape nach ＋: nimmt den Klick samt getipptem Filter zurück, auch wenn sich das
    /// Menü ohne Treffer schon geschlossen hat; ein zuvor leerer Absatz bleibt leer.
    /// Per Undo nur, wenn der Schritt „Neuer Block“ genau oben liegt, sonst als eigene
    /// Bearbeitung. Nie mehrere Undo-Schritte. `true`, wenn zurückgenommen.
    @discardableResult
    func revertInsertBlockWithMenu() -> Bool {
        guard let pending = pendingInsert else { return false }
        pendingInsert = nil
        guard !textView.hasMarkedText(),
              let index = document.blocks.firstIndex(where: { $0.id == pending.blockID }),
              document[index].text.hasPrefix("/") else { return false }
        textView.breakUndoCoalescing()
        if document == pending.documentAfterInsert, undoManager.canUndo,
           undoManager.undoActionName == UndoAction.newBlock {
            undoManager.undo()
        } else {
            var newDocument = document
            if pending.reusedEmptyParagraph {
                newDocument.blocks[index].content = InlineText()
            } else {
                _ = newDocument.deleteBlock(at: index)
                newDocument.ensureEditableEnd()
            }
            apply(newDocument, cursor: nil, actionName: UndoAction.delete)
        }
        if NSMaxRange(pending.selectionBefore) < textView.string.utf16.count {
            textView.setSelectedRange(pending.selectionBefore)
        }
        return true
    }

    /// Ändert die Art des Blocks am Cursor (Slash-Menü).
    func setKind(_ kind: BlockKind, ofBlockAtCharacter location: Int) {
        let index = blockIndex(atCharacter: location)
        var newDocument = document
        newDocument.setKind(kind, at: index)
        var cursor = BlockPosition(block: index, offset: newDocument[index].length)
        if kind.isAtomic { cursor = BlockPosition(block: index + 1, offset: 0) }
        apply(newDocument, cursor: cursor, actionName: UndoAction.changeKind)
    }
}
#endif
