#if os(macOS)
import AppKit
import QuillDesign

extension NSPasteboard.PasteboardType {
    /// Quill-Blöcke als JSON (`[EditorBlock]`).
    static let quillBlocks = NSPasteboard.PasteboardType("de.vogel.quill.blocks")
    static let markdown = NSPasteboard.PasteboardType("net.daringfireball.markdown")
    /// Interner Ziehvorgang: IDs der gezogenen Blöcke.
    static let quillBlockDrag = NSPasteboard.PasteboardType("de.vogel.quill.block-drag")
}

/// Text-View des Block-Editors. Strukturelle Logik liegt im `BlockEditorController`;
/// hier sitzen nur Ereignisse, die eine View braucht.
final class BlockTextView: NSTextView {
    weak var editor: BlockEditorController?

    private let handle = BlockHandleView()
    private let dropIndicator = NSView()
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        handle.isHidden = true
        handle.textView = self
        addSubview(handle)
        dropIndicator.wantsLayer = true
        dropIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dropIndicator.layer?.cornerRadius = 1
        dropIndicator.isHidden = true
        addSubview(dropIndicator)
    }

    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    // MARK: Layout: zentrierte Textspalte

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let side = max(56, (newSize.width - QuillDesign.contentMaxWidth) / 2)
        if abs(textContainerInset.width - side) > 0.5 {
            textContainerInset = NSSize(width: side, height: 48)
        }
    }

    // MARK: Auswahl nie hinter das abschließende `\n` des letzten Blocks

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        let limit = max(0, (textStorage?.length ?? 0) - 1)
        let clamped = ranges.map { value -> NSValue in
            let range = value.rangeValue
            let location = min(range.location, limit)
            let end = min(NSMaxRange(range), limit)
            return NSValue(range: NSRange(location: location, length: max(0, end - location)))
        }
        super.setSelectedRanges(clamped, affinity: affinity, stillSelecting: stillSelecting)
    }

    // MARK: Fragmente

    func containerPoint(for viewPoint: NSPoint) -> CGPoint {
        CGPoint(x: viewPoint.x - textContainerOrigin.x, y: viewPoint.y - textContainerOrigin.y)
    }

    func fragment(atViewPoint point: NSPoint) -> BlockLayoutFragment? {
        textLayoutManager?.textLayoutFragment(for: containerPoint(for: point)) as? BlockLayoutFragment
    }

    func characterOffset(of fragment: NSTextLayoutFragment) -> Int? {
        guard let manager = textLayoutManager, let contentManager = manager.textContentManager else { return nil }
        return contentManager.offset(from: contentManager.documentRange.location, to: fragment.rangeInElement.location)
    }

    /// Rahmen eines Fragments in View-Koordinaten.
    func viewFrame(of fragment: NSTextLayoutFragment) -> CGRect {
        fragment.layoutFragmentFrame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    // MARK: Checkbox

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let fragment = fragment(atViewPoint: point), fragment.kind == .todo,
           let offset = characterOffset(of: fragment) {
            let frame = viewFrame(of: fragment)
            let box = fragment.checkboxRect.offsetBy(dx: frame.minX, dy: frame.minY).insetBy(dx: -4, dy: -4)
            if box.contains(point) {
                editor?.toggleChecked(atCharacter: offset)
                return
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: Griff bei Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHandle(for: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if !handle.frame.insetBy(dx: -8, dy: -8).contains(point) { handle.isHidden = true }
    }

    private func updateHandle(for point: NSPoint) {
        guard let fragment = fragment(atViewPoint: CGPoint(x: textContainerOrigin.x + 1, y: point.y)),
              let offset = characterOffset(of: fragment) else {
            handle.isHidden = true
            return
        }
        let frame = viewFrame(of: fragment)
        let lineTop = fragment.textLineFragments.first.map { $0.typographicBounds.minY } ?? 0
        let lineHeight = fragment.textLineFragments.first.map { $0.typographicBounds.height } ?? 20
        let x = textContainerOrigin.x + BlockStyle.textInset(kind: fragment.kind, indent: fragment.indent)
            - (fragment.kind.isListItem ? QuillDesign.Spacing.indentStep : 0) - 26
        handle.frame = CGRect(x: x, y: frame.minY + lineTop + (lineHeight - 22) / 2, width: 20, height: 22)
        handle.characterOffset = offset
        handle.isHidden = false
    }

    // MARK: Ziehen und Ablegen von Blöcken

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [.quillBlockDrag]
    }

    private func isBlockDrag(_ info: any NSDraggingInfo) -> Bool {
        info.draggingPasteboard.availableType(from: [.quillBlockDrag]) != nil
    }

    /// Zielindex (Block) und y-Position der Einfügelinie.
    private func dropTarget(for info: any NSDraggingInfo) -> (index: Int, y: CGFloat)? {
        let point = convert(info.draggingLocation, from: nil)
        guard let editor else { return nil }
        guard let fragment = fragment(atViewPoint: CGPoint(x: textContainerOrigin.x + 1, y: point.y)),
              let offset = characterOffset(of: fragment) else {
            return (editor.document.count, bounds.maxY)
        }
        let frame = viewFrame(of: fragment)
        let block = editor.blockIndex(atCharacter: offset)
        return point.y < frame.midY ? (block, frame.minY) : (block + 1, frame.maxY)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isBlockDrag(sender) ? draggingUpdated(sender) : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isBlockDrag(sender) else { return super.draggingUpdated(sender) }
        guard let target = dropTarget(for: sender) else { return [] }
        let left = textContainerOrigin.x
        dropIndicator.frame = CGRect(x: left, y: target.y - 1, width: bounds.width - 2 * left, height: 2)
        dropIndicator.isHidden = false
        return .move
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dropIndicator.isHidden = true
        super.draggingExited(sender)
    }

    /// `NSTextView` lehnt unbekannte Typen hier ab; Block-Drags erledigt `performDragOperation`.
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isBlockDrag(sender) ? true : super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isBlockDrag(sender) else { return super.performDragOperation(sender) }
        dropIndicator.isHidden = true
        guard let target = dropTarget(for: sender),
              let data = sender.draggingPasteboard.data(forType: .quillBlockDrag),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return false }
        return editor?.moveBlocks(withIDs: ids, to: target.index) ?? false
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        dropIndicator.isHidden = true
        super.concludeDragOperation(sender)
    }

    /// Wird auch bei Abbruch aufgerufen; die Einfügelinie darf nie stehen bleiben.
    override func draggingEnded(_ sender: any NSDraggingInfo) {
        dropIndicator.isHidden = true
        super.draggingEnded(sender)
    }

    // MARK: Zwischenablage

    override func copy(_ sender: Any?) {
        if editor?.copySelection(to: .general) != true { super.copy(sender) }
    }

    override func cut(_ sender: Any?) {
        if editor?.cutSelection(to: .general) != true { super.cut(sender) }
    }

    override func paste(_ sender: Any?) {
        if editor?.paste(from: .general) != true { super.paste(sender) }
    }
}

/// Griff ⋮⋮ links neben einem Block; startet das Ziehen.
final class BlockHandleView: NSView, NSDraggingSource {
    weak var textView: BlockTextView?
    var characterOffset = 0

    override func draw(_ dirtyRect: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        guard let image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Block verschieben")?
            .withSymbolConfiguration(config) else { return }
        NSColor.tertiaryLabelColor.set()
        let size = image.size
        let rect = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        image.draw(in: rect)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let textView, let editor = textView.editor else { return }
        let blocks = editor.dragBlocks(forHandleAtCharacter: characterOffset)
        guard !blocks.ids.isEmpty, let data = try? JSONEncoder().encode(blocks.ids) else { return }

        let item = NSPasteboardItem()
        item.setData(data, forType: .quillBlockDrag)
        item.setString(blocks.markdown, forType: .string)
        item.setString(blocks.markdown, forType: .markdown)

        let dragging = NSDraggingItem(pasteboardWriter: item)
        let frame = blocks.viewFrame
        let image = NSImage(size: frame.size)
        if let rep = textView.bitmapImageRepForCachingDisplay(in: frame) {
            textView.cacheDisplay(in: frame, to: rep)
            image.addRepresentation(rep)
        }
        let local = convert(frame, from: textView)
        dragging.setDraggingFrame(local, contents: image)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : .copy
    }
}
#endif
