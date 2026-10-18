#if canImport(AppKit)
import AppKit
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
        Self.keepEditableEnd(&newDocument)
        textView.breakUndoCoalescing()
        apply(newDocument, cursor: nil, actionName: UndoAction.moveBlocks)
        textView.setSelectedRange(NSRange(location: paragraphStarts[moved.lowerBound] + offset, length: selection.length))
        return true
    }

    /// ⌘D: Blöcke der Auswahl darunter verdoppeln und die Kopien auswählen. Bilder
    /// bekommen eine Kopie ihres Assets (das dauert, deshalb dann asynchron).
    func duplicateSelectedBlocks() {
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
        guard !blocks.isEmpty, let anchor = document.blocks.firstIndex(where: { $0.id == anchorID }) else { return }
        var newDocument = document
        for (offset, block) in blocks.enumerated() {
            var copy = block
            copy.id = UUID()
            newDocument.insertBlock(copy, at: anchor + 1 + offset)
        }
        textView.breakUndoCoalescing()
        apply(newDocument, cursor: nil, actionName: UndoAction.duplicate)
        selectBlocks((anchor + 1)...(anchor + blocks.count))
    }

    /// Kontextmenü „Löschen“: Blöcke der Auswahl entfernen, ein Undo-Schritt.
    func deleteSelectedBlocks() {
        let range = selectedBlockRange()
        var newDocument = document
        var cursor = BlockPosition(block: 0, offset: 0)
        for index in range.reversed() {
            cursor = newDocument.deleteBlock(at: index)
        }
        Self.keepEditableEnd(&newDocument)
        textView.breakUndoCoalescing()
        apply(newDocument, cursor: cursor, actionName: UndoAction.delete)
    }

    /// Hinter einem Trenner oder Bild am Ende muss ein Absatz zum Weiterschreiben stehen.
    static func keepEditableEnd(_ document: inout EditorDocument) {
        if document.blocks.last?.kind.isAtomic ?? true {
            document.blocks.append(EditorBlock())
        }
    }
}
#endif
