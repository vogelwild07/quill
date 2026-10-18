#if canImport(AppKit)
import AppKit

/// Ziehen von Blöcken am Griff.
extension BlockEditorController {
    /// Zu ziehende Blöcke: die ausgewählten, wenn der Griff zur Auswahl gehört, sonst der eine Block.
    func dragBlocks(forHandleAtCharacter location: Int) -> (ids: [UUID], markdown: String, viewFrame: CGRect) {
        let range = handleBlockRange(atCharacter: location)
        let ids = range.map { document[$0].id }
        let markdown = MarkdownSerializer.markdown(for: document, blocks: range.lowerBound..<(range.upperBound + 1))

        var frame = CGRect.null
        if let manager = textView.textLayoutManager, let content = manager.textContentManager {
            let start = paragraphStarts[range.lowerBound]
            let end = paragraphStarts[range.upperBound + 1]
            if let from = content.location(content.documentRange.location, offsetBy: start),
               let to = content.location(content.documentRange.location, offsetBy: end - 1),
               let textRange = NSTextRange(location: from, end: to) {
                manager.enumerateTextLayoutFragments(from: textRange.location, options: [.ensuresLayout]) { fragment in
                    frame = frame.union(self.textView.viewFrame(of: fragment))
                    return fragment.rangeInElement.endLocation.compare(textRange.endLocation) == .orderedAscending
                }
            }
        }
        if frame.isNull { frame = CGRect(x: 0, y: 0, width: 200, height: 24) }
        return (ids, markdown, frame)
    }

    /// Verschiebt Blöcke vor den Block mit Index `destination` (vor dem Verschieben).
    @discardableResult
    func moveBlocks(withIDs ids: [UUID], to destination: Int) -> Bool {
        let wanted = Set(ids)
        let indices = IndexSet(document.blocks.indices.filter { wanted.contains(document[$0].id) })
        guard !indices.isEmpty else { return false }
        if let first = indices.first, let last = indices.last, last - first + 1 == indices.count,
           (first...(last + 1)).contains(destination) {
            return false
        }
        var newDocument = document
        let range = newDocument.moveBlocks(indices, to: destination)
        apply(newDocument, cursor: nil, actionName: UndoAction.moveBlocks)
        let start = paragraphStarts[range.lowerBound]
        let end = paragraphStarts[range.upperBound] - 1
        textView.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
        return true
    }
}
#endif
