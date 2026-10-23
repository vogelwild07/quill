#if canImport(AppKit)
import AppKit
import QuillEditorCore
import QuillModel

/// Zeichen am rechten Rand eines Blocks (11.6): Konflikt aus dem Abgleich,
/// „wiederhergestellt“ oder geplante Erinnerung (15.4). Ein Klick (oder Drücken per Bedienungshilfen) zeigt ein
/// Popover; den Inhalt liefert die App (`markerPopoverContent`).
extension BlockEditorController {
    /// Blöcke mit Konflikt aus dem letzten Abgleich.
    public var conflictBlocks: Set<UUID> {
        get { layoutDelegate.conflictBlocks }
        set {
            guard newValue != layoutDelegate.conflictBlocks else { return }
            let changed = newValue.symmetricDifference(layoutDelegate.conflictBlocks)
            layoutDelegate.conflictBlocks = newValue
            redrawBlocks(changed)
        }
    }

    /// To-dos mit geplanter Erinnerung (15.4); die App kennt sie, das Dokument nicht.
    public var reminderBlocks: Set<UUID> {
        get { layoutDelegate.reminderBlocks }
        set {
            guard newValue != layoutDelegate.reminderBlocks else { return }
            let changed = newValue.symmetricDifference(layoutDelegate.reminderBlocks)
            layoutDelegate.reminderBlocks = newValue
            redrawBlocks(changed)
        }
    }

    /// Entfernt die Marke „wiederhergestellt“ eines Blocks; ein Undo-Schritt.
    public func clearRestored(blockID: UUID) {
        guard !textView.hasMarkedText(), let index = document.blocks.firstIndex(where: { $0.id == blockID }),
              document[index].isRestored
        else { return }
        let selection = textView.selectedRange()
        var newDocument = document
        newDocument.blocks[index].isRestored = false
        textView.breakUndoCoalescing()
        apply(newDocument, cursor: nil, actionName: UndoAction.clearRestored)
        textView.setSelectedRange(selection)
    }

    public func closeMarkerPopover() {
        markerPopover?.close()
        markerPopover = nil
    }

    /// Blöcke, die gerade ein Zeichen tragen, in Dokumentreihenfolge.
    func markedBlocks() -> [(id: UUID, marker: BlockMarker)] {
        document.blocks.compactMap { block in
            if conflictBlocks.contains(block.id) { return (block.id, .conflict) }
            if block.isRestored { return (block.id, .restored) }
            return reminderBlocks.contains(block.id) ? (block.id, .reminder) : nil
        }
    }

    /// Zeigt das Popover zum Zeichen eines Blocks.
    @discardableResult
    func showMarkerPopover(blockID: UUID) -> Bool {
        guard let marked = markedBlocks().first(where: { $0.id == blockID }),
              let content = markerPopoverContent?(blockID, marked.marker),
              let rect = textView.markerViewFrame(ofBlock: blockID)
        else { return false }
        markerPopover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = content
        popover.show(relativeTo: rect, of: textView, preferredEdge: .maxX)
        // Sonst meldet der Audit das Popover als Element ohne Beschreibung.
        content.view.window?.setAccessibilityLabel(textView.markerHelp(marked.marker))
        markerPopover = popover
        return true
    }

    private func redrawBlocks(_ ids: Set<UUID>) {
        guard let manager = textView.textLayoutManager, let content = manager.textContentManager else { return }
        for (index, block) in document.blocks.enumerated() where ids.contains(block.id) {
            let range = paragraphRange(ofBlock: index)
            guard let start = content.location(content.documentRange.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end)
            else { continue }
            manager.invalidateRenderingAttributes(for: textRange)
            manager.invalidateLayout(for: textRange)
        }
        textView.needsLayout = true
        textView.needsDisplay = true
    }
}

extension BlockTextView {
    /// Rahmen des Zeichens eines Blocks in View-Koordinaten.
    func markerViewFrame(ofBlock blockID: UUID) -> CGRect? {
        guard let editor, let layoutManager = textLayoutManager,
              let index = editor.document.blocks.firstIndex(where: { $0.id == blockID }),
              let start = layoutManager.location(layoutManager.documentRange.location,
                                                 offsetBy: editor.paragraphRange(ofBlock: index).location)
        else { return nil }
        layoutManager.ensureLayout(for: NSTextRange(location: start))
        guard let fragment = layoutManager.textLayoutFragment(for: start) as? BlockLayoutFragment else { return nil }
        let frame = viewFrame(of: fragment)
        return fragment.markerRect.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    /// Klick auf ein Zeichen am rechten Rand; `true`, wenn eines getroffen wurde.
    func handleMarkerClick(at point: NSPoint) -> Bool {
        guard let fragment = fragment(atViewPoint: CGPoint(x: textContainerOrigin.x + 1, y: point.y)),
              fragment.marker != nil, let blockID = fragment.blockID
        else { return false }
        let frame = viewFrame(of: fragment)
        guard fragment.markerRect.offsetBy(dx: frame.minX, dy: frame.minY).insetBy(dx: -4, dy: -4).contains(point) else {
            return false
        }
        return editor?.showMarkerPopover(blockID: blockID) ?? false
    }

    /// Zeichen für VoiceOver und XCUITest, je Block ein Element.
    func markerAccessibilityElements() -> [MarkerAccessibilityElement] {
        guard let editor else { return [] }
        var kept: [UUID: MarkerAccessibilityElement] = [:]
        var result: [MarkerAccessibilityElement] = []
        for (id, marker) in editor.markedBlocks() {
            let element = markerElements[id].flatMap { $0.marker == marker ? $0 : nil }
                ?? MarkerAccessibilityElement(blockID: id, marker: marker, textView: self)
            kept[id] = element
            result.append(element)
        }
        markerElements = kept
        return result
    }

    func markerScreenFrame(ofBlock blockID: UUID) -> NSRect {
        guard let window, let rect = markerViewFrame(ofBlock: blockID) else { return .zero }
        return window.convertToScreen(convert(rect, to: nil))
    }

    func markerHelp(_ marker: BlockMarker) -> String {
        switch marker {
        case .conflict: String(localized: "Zwei Fassungen nach dem Abgleich, zum Wählen klicken", bundle: .module)
        case .restored: String(localized: "Wiederhergestellt nach dem Abgleich", bundle: .module)
        case .reminder: String(localized: "Erinnerung geplant, zum Ansehen klicken", bundle: .module)
        }
    }

    func markerLabel(ofBlock blockID: UUID, marker: BlockMarker) -> String {
        let text = editor?.document.blocks.first { $0.id == blockID }?.text ?? ""
        let help = markerHelp(marker)
        return text.isEmpty ? help : String(localized: "\(help): \(String(text.prefix(40)))", bundle: .module)
    }
}

/// Zeichen am Rand als Knopf für die Bedienungshilfen; Drücken öffnet das Popover.
final class MarkerAccessibilityElement: NSAccessibilityElement {
    let blockID: UUID
    let marker: BlockMarker
    nonisolated(unsafe) private weak var textView: BlockTextView?

    init(blockID: UUID, marker: BlockMarker, textView: BlockTextView) {
        self.blockID = blockID
        self.marker = marker
        self.textView = textView
        super.init()
        switch marker {
        case .conflict: setAccessibilityIdentifier("editor.marker.conflict")
        case .restored: setAccessibilityIdentifier("editor.marker.restored")
        case .reminder: setAccessibilityIdentifier("editor.marker.reminder")
        }
    }

    override func isAccessibilityElement() -> Bool { true }

    override func isAccessibilityEnabled() -> Bool { true }

    override func accessibilityParent() -> Any? { textView }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilityLabel() -> String? {
        let (view, id, marker) = (textView, blockID, marker)
        return MainActor.assumeIsolated { view?.markerLabel(ofBlock: id, marker: marker) }
    }

    override func accessibilityFrame() -> NSRect {
        let (view, id) = (textView, blockID)
        return MainActor.assumeIsolated { view?.markerScreenFrame(ofBlock: id) ?? .zero }
    }

    override func accessibilityPerformPress() -> Bool {
        let (view, id) = (textView, blockID)
        return MainActor.assumeIsolated { view?.editor?.showMarkerPopover(blockID: id) ?? false }
    }
}
#endif
