#if canImport(AppKit)
import AppKit
import QuillEditorCore
import SwiftUI

/// Einbettung des Editors in eine Seite: Kopf, Fokus, Neuladen.
extension BlockEditorController {
    /// Kopf über dem ersten Block, z. B. `EditorHeaderView` mit Icon und Titel.
    public var header: NSView? {
        get { textView.headerView }
        set { textView.headerView = newValue }
    }

    /// Abstand über dem Kopf (Design: 96 pt).
    public var topPadding: CGFloat {
        get { textView.topPadding }
        set { textView.topPadding = newValue }
    }

    public var isEditable: Bool {
        get { textView.isEditable }
        set { textView.isEditable = newValue }
    }

    /// Ohne Markieren und Schreibmarke, z. B. beim Präsentieren: Der Editor nimmt keinen
    /// Fokus, Tasten gehen an die umgebende Ansicht.
    public var isSelectable: Bool {
        get { textView.isSelectable }
        set { textView.isSelectable = newValue }
    }

    /// Lesemodus, z. B. für frühere Stände in der Zeitreise: Markieren, Kopieren und die
    /// Schreibmarke gehen wie sonst (auch per Tastatur, ⇧↓), jede Änderung wird abgelehnt.
    /// Anders als `isEditable = false`: Ohne Schreibmarke scrollen Pfeiltasten nur.
    public var isReadOnly: Bool {
        get { textView.isReadOnly }
        set { textView.isReadOnly = newValue }
    }

    /// IDs der Blöcke, die die Markierung berührt, in Dokument-Reihenfolge; leer ohne
    /// markierten Text (nur Cursor), z. B. für „Auswahl zurückholen“ in der Zeitreise.
    public var selectedBlockIDs: [UUID] {
        let selection = textView.selectedRange()
        guard selection.length > 0 else { return [] }
        let first = blockIndex(atCharacter: selection.location)
        let last = blockIndex(atCharacter: NSMaxRange(selection) - 1)
        return document.blocks[first...last].map(\.id)
    }

    /// Block an der Einfügemarke (Anfang der Auswahl); `nil` ohne Blöcke.
    public var cursorBlockID: UUID? {
        guard !document.blocks.isEmpty else { return nil }
        return document.blocks[blockIndex(atCharacter: textView.selectedRange().location)].id
    }

    /// Setzt den Cursor an den Anfang des ersten Blocks und fokussiert den Editor
    /// (↩ im Titel).
    public func focusStart() {
        focus()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        updateTypingAttributes(forCaretAt: BlockPosition(block: 0, offset: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    /// Ersetzt das Dokument nach einer Änderung aus einem anderen Fenster.
    /// Die Auswahl bleibt an derselben Stelle, soweit es sie noch gibt.
    /// Bei markiertem Text (IME, tote Tasten) wird nicht eingegriffen: `false`.
    @discardableResult
    public func reload(_ newDocument: EditorDocument) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        guard newDocument != document else { return true }
        let selection = textView.selectedRange()
        // Cursor als Block und Abstand darin merken: Kam davor Text hinzu (Sync, anderes
        // Fenster), bliebe er sonst an der alten Stelle und Tippen landete daneben.
        let old = document
        let start = mapped(selection.location, from: old, to: newDocument)
        let end = mapped(NSMaxRange(selection), from: old, to: newDocument)
        load(newDocument)
        let limit = max(0, (textView.textStorage?.length ?? 1) - 1)
        let location = min(start ?? selection.location, limit)
        let length = end.map { max(0, $0 - location) } ?? selection.length
        textView.setSelectedRange(NSRange(location: location, length: min(length, limit - location)))
        return true
    }

    /// Stelle im Textspeicher nach dem Neuladen, wenn es den Block noch gibt; `nil` sonst.
    private func mapped(_ location: Int, from old: EditorDocument, to new: EditorDocument) -> Int? {
        guard !old.blocks.isEmpty else { return nil }
        let index = blockIndex(atCharacter: location)
        guard old.blocks.indices.contains(index), paragraphStarts.indices.contains(index) else { return nil }
        let block = old[index]
        guard let newIndex = new.blocks.firstIndex(where: { $0.id == block.id }) else { return nil }
        let offset = min(location - paragraphStarts[index], BlockRenderer.displayLength(of: block))
        let newBlock = new[newIndex]
        let newOffset = min(BlockMerge.mappedOffset(offset, from: block.text, to: newBlock.text), BlockRenderer.displayLength(of: newBlock))
        var start = 0
        for earlier in new.blocks[..<newIndex] { start += BlockRenderer.displayLength(of: earlier) + 1 }
        return start + newOffset
    }

    /// Springt zu einem Block, wählt `range` darin aus (UTF-16 im Blocktext) und
    /// fokussiert den Editor, z. B. für einen Inhaltstreffer aus „Schnell öffnen“.
    /// Ein Bereich außerhalb des Blocks wird gekürzt. `false`, wenn es den Block nicht gibt.
    @discardableResult
    public func reveal(blockID: UUID, range: NSRange) -> Bool {
        guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else { return false }
        let length = BlockRenderer.displayLength(of: document[index])
        let start = range.location == NSNotFound ? 0 : min(max(0, range.location), length)
        let end = min(start + max(0, range.length), length)
        let selection = NSRange(location: paragraphStarts[index] + start, length: end - start)
        focus()
        textView.setSelectedRange(selection)
        updateTypingAttributes(forCaretAt: BlockPosition(block: index, offset: start))
        textView.scrollRangeToVisible(selection)
        if selection.length > 0 { textView.showFindIndicator(for: selection) }
        return true
    }

    /// `true`, wenn der Cursor in der ersten Zeile des Dokuments steht (↑ geht dann in den Titel).
    func isCaretOnFirstLine() -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0, blockIndex(atCharacter: selection.location) == 0 else { return false }
        if selection.location == 0 { return true }
        let caret = textView.firstRect(forCharacterRange: NSRange(location: selection.location, length: 0), actualRange: nil)
        let start = textView.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
        return abs(caret.midY - start.midY) < 1
    }
}

/// Kopf aus SwiftUI über dem ersten Block. Meldet seine Höhe zur Textbreite und
/// stößt bei Größenänderungen (z. B. mehrzeiliger Titel) das Layout der Text-View an.
public final class EditorHeaderView: NSView, HeaderSizing {
    private let hosting: NSHostingController<AnyView>
    private var sizeObservation: NSKeyValueObservation?

    public init(rootView: some View) {
        hosting = NSHostingController(rootView: AnyView(rootView))
        hosting.sizingOptions = [.preferredContentSize]
        super.init(frame: .zero)
        hosting.view.frame = bounds
        hosting.view.autoresizingMask = [.width, .height]
        addSubview(hosting.view)
        // Für VoiceOver eine Gruppe; die Beschriftung setzt, wer den Kopf baut.
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        sizeObservation = hosting.observe(\.preferredContentSize) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.superview?.needsLayout = true }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    func height(forWidth width: CGFloat) -> CGFloat {
        hosting.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    override public var isFlipped: Bool { true }
}
#endif
