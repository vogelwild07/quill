#if canImport(AppKit)
import AppKit
import QuillEditorCore
import QuillModel

/// Aktionen auf ganze Blöcke: verschieben per Tastatur, duplizieren, löschen.
/// Aufgerufen aus dem Menü „Format“ und aus dem Kontextmenü am Griff.
extension BlockEditorController {
    /// Blöcke, auf die der Griff wirkt: die Auswahl, wenn der Griff dazugehört, sonst sein Block.
    func handleBlockRange(atCharacter location: Int) -> ClosedRange<Int> {
        let handleBlock = blockIndex(atCharacter: location)
        let selected = selectedBlockRange()
        if textView.selectedRange().length > 0, selected.contains(handleBlock) { return selected }
        return handleBlock...handleBlock
    }

    /// Wählt den Text der Blöcke aus (ohne den abschließenden Zeilenumbruch).
    func selectBlocks(_ range: ClosedRange<Int>) {
        let start = paragraphStarts[range.lowerBound]
        let end = paragraphStarts[range.upperBound + 1] - 1
        textView.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
    }

    /// ⌥⌘↑/↓: Blöcke der Auswahl um eine Stelle verschieben; Cursor bzw. Auswahl wandern mit.
    @discardableResult
    func moveSelectedBlocks(by delta: Int) -> Bool {
        guard !textView.hasMarkedText(), delta != 0 else { return false }
        let range = selectedBlockRange()
        let destination = delta < 0 ? range.lowerBound - 1 : range.upperBound + 2
        guard destination >= 0, destination <= document.count else { return false }
        let selection = textView.selectedRange()
        let offset = selection.location - paragraphStarts[range.lowerBound]
        var newDocument = document
        let moved = newDocument.moveBlocks(IndexSet(integersIn: range), to: destination)
        newDocument.ensureEditableEnd()
        textView.breakUndoCoalescing()
        apply(newDocument, cursor: nil, actionName: UndoAction.moveBlocks)
        textView.setSelectedRange(NSRange(location: paragraphStarts[moved.lowerBound] + offset, length: selection.length))
        return true
    }

    /// ⌘D: Blöcke der Auswahl darunter verdoppeln und die Kopien auswählen. Bilder
    /// bekommen eine Kopie ihres Assets (das dauert, deshalb dann asynchron).
    func duplicateSelectedBlocks() {
        guard !textView.hasMarkedText() else { return }
        let range = selectedBlockRange()
        let originals = range.map { document[$0] }
        let anchorID = document[range.upperBound].id
        guard originals.contains(where: { $0.kind == .image }) else {
            insertDuplicates(originals, after: anchorID)
            return
        }
        Task {
            insertDuplicates(await withDuplicatedAssets(originals), after: anchorID)
        }
    }

    private func insertDuplicates(_ blocks: [EditorBlock], after anchorID: UUID) {
        insertBlocks(blocks.map { $0.withNewID() }, after: anchorID, actionName: UndoAction.duplicate)
    }

    /// Blöcke unter dem Block `anchorID` einfügen und auswählen, ein Schritt für ⌘Z
    /// (⌘D, To-dos aus der KI). Fehlt der Block inzwischen, passiert nichts.
    public func insertBlocks(_ blocks: [EditorBlock], after anchorID: UUID, actionName: String) {
        guard !blocks.isEmpty, textView.canEdit, !textView.hasMarkedText(),
              let anchor = document.blocks.firstIndex(where: { $0.id == anchorID }) else { return }
        var newDocument = document
        for (offset, block) in blocks.enumerated() {
            newDocument.insertBlock(block, at: anchor + 1 + offset)
        }
        textView.breakUndoCoalescing()
        apply(newDocument, cursor: nil, actionName: actionName)
        selectBlocks((anchor + 1)...(anchor + blocks.count))
    }

    /// Kontextmenü „Löschen“: Blöcke der Auswahl entfernen, ein Undo-Schritt.
    func deleteSelectedBlocks() {
        guard !textView.hasMarkedText() else { return }
        let range = selectedBlockRange()
        var newDocument = document
        var cursor = BlockPosition(block: 0, offset: 0)
        for index in range.reversed() {
            cursor = newDocument.deleteBlock(at: index)
        }
        newDocument.ensureEditableEnd()
        textView.breakUndoCoalescing()
        apply(newDocument, cursor: cursor, actionName: UndoAction.delete)
    }
}
#endif
