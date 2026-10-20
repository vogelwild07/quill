#if canImport(AppKit)
import AppKit
import QuillEditorCore

/// Abgleich Textspeicher → Modell nach nativen Edits der Text-View und nach Undo/Redo.
extension BlockEditorController: @MainActor NSTextStorageDelegate {
    public func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range: NSRange,
        changeInLength delta: Int
    ) {
        guard !isApplying, editedMask.contains(.editedCharacters) else { return }
        editedRange = editedRange.map { NSUnionRange($0, range) } ?? range
        editedDelta += delta
    }

    /// Undo/Redo der Text-View löst kein `textDidChange` aus; danach das Modell neu lesen.
    /// Beobachtet nur den eigenen `undoManager`.
    func observeUndo() {
        undoObservations = [NSNotification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange].map { name in
            NotificationObservation(name, object: undoManager) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.slashMenu.close()
                    self.syncFromStorage()
                }
            }
        }
    }

    /// Schneller Pfad für normales Tippen: Die Änderung liegt in genau einem Absatz und
    /// hat keine Blockgrenze erzeugt oder entfernt. Dann nur diesen Block nachführen.
    func syncSingleParagraph() -> Bool {
        guard let storage = textView.textStorage, let editedRange else { return false }
        let string = storage.string as NSString
        guard paragraphStarts[document.count] + editedDelta == string.length else { return false }

        let index = blockIndex(atCharacter: editedRange.location)
        let start = paragraphStarts[index]
        let newEnd = paragraphStarts[index + 1] + editedDelta - 1
        guard newEnd >= start, newEnd < string.length, NSMaxRange(editedRange) <= newEnd,
              string.character(at: newEnd) == StorageCharacter.paragraphEnd,
              !document[index].kind.isAtomic else { return false }
        let body = NSRange(location: start, length: newEnd - start)
        guard string.rangeOfCharacter(from: CharacterSet(charactersIn: "\n"), options: [], range: body).location == NSNotFound
        else { return false }

        let expectedID = document[index].id.uuidString
        if editedRange.length > 0,
           storage.attribute(.quillBlockID, at: editedRange.location, effectiveRange: nil) as? String != expectedID {
            return false
        }
        document[index].text = string.substring(with: body).replacingOccurrences(of: StorageCharacter.softBreak, with: "\n")
        if document[index].kind.allowsInlineMarks {
            document[index].spans = BlockRenderer.spans(in: storage, body: body)
        }
        for later in (index + 1)...document.count { paragraphStarts[later] += editedDelta }
        self.editedRange = nil
        editedDelta = 0
        onChange?(document)
        return true
    }

    /// Modell aus dem Textspeicher lesen, Attribute der bearbeiteten Absätze vereinheitlichen.
    func syncFromStorage() {
        guard let storage = textView.textStorage else { return }
        let (blocks, repaired) = BlockRenderer.parse(storage)
        document = EditorDocument(blocks: blocks)
        rebuildParagraphStarts()

        var normalize = repaired
        if let editedRange {
            let string = storage.string as NSString
            let clamped = NSIntersectionRange(editedRange, NSRange(location: 0, length: string.length))
            normalize.append(string.paragraphRange(for: clamped))
        }
        editedRange = nil
        editedDelta = 0

        let ordinals = BlockRenderer.ordinals(for: document)
        isApplying = true
        storage.beginEditing()
        for range in normalize where range.length > 0 {
            let first = blockIndex(atCharacter: range.location)
            let last = blockIndex(atCharacter: NSMaxRange(range) - 1)
            for index in first...last {
                let block = document[index]
                BlockRenderer.restyle(storage, block: block, ordinal: ordinals[block.id], range: paragraphRange(ofBlock: index))
            }
        }
        storage.endEditing()
        isApplying = false
        refreshOrdinals()
        loadMissingImages()
        onChange?(document)
    }
}
#endif
