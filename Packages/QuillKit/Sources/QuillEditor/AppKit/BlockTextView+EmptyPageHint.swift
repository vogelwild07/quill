#if canImport(AppKit)
import AppKit

/// Hinweis auf einer leeren Seite: nur gezeichnet, nie im Textspeicher. So wird er
/// nie gespeichert, exportiert oder kopiert. Sichtbar, solange die Seite genau einen
/// leeren Textabsatz hat und kein markierter Text (IME) ansteht; das erste Zeichen
/// blendet ihn aus. VoiceOver liest ihn als Platzhalter.
extension BlockTextView {
    static var emptyPageHint: String {
        String(localized: "Leere Seite – mit „/“ wählst du eine Blockart.", bundle: .module)
    }

    var showsEmptyPageHint: Bool {
        guard let editor, editor.document.count == 1, textStorage?.length == 1, !hasMarkedText() else { return false }
        let block = editor.document[0]
        return block.kind == .paragraph && block.text.isEmpty
    }

    /// Nach jeder Änderung des Dokuments; zeichnet nur neu, wenn sich etwas ändert.
    func updateEmptyPageHint() {
        let visible = showsEmptyPageHint
        guard visible != isShowingEmptyPageHint else { return }
        isShowingEmptyPageHint = visible
        needsDisplay = true
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        updateEmptyPageHint()
    }

    override func unmarkText() {
        super.unmarkText()
        updateEmptyPageHint()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsEmptyPageHint, let rect = emptyPageHintRect else { return }
        var attributes = typingAttributes
        attributes[.foregroundColor] = NSColor.placeholderTextColor
        NSAttributedString(string: Self.emptyPageHint, attributes: attributes)
            .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    /// Erste Zeile des leeren Absatzes in View-Koordinaten.
    var emptyPageHintRect: CGRect? {
        guard let manager = textLayoutManager,
              let fragment = manager.textLayoutFragment(for: manager.documentRange.location),
              let line = fragment.textLineFragments.first else { return nil }
        let frame = viewFrame(of: fragment)
        let width = (textContainer?.size.width ?? frame.width) - 2 * (textContainer?.lineFragmentPadding ?? 0)
        return CGRect(
            x: frame.minX + line.typographicBounds.minX,
            y: frame.minY + line.typographicBounds.minY,
            width: max(0, width),
            height: line.typographicBounds.height
        )
    }

    override func accessibilityPlaceholderValue() -> String? {
        showsEmptyPageHint ? Self.emptyPageHint : nil
    }
}
#endif
