#if canImport(AppKit)
import AppKit
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
    public func reload(_ newDocument: EditorDocument) {
        guard newDocument != document else { return }
        let selection = textView.selectedRange()
        load(newDocument)
        let limit = max(0, (textView.textStorage?.length ?? 1) - 1)
        let location = min(selection.location, limit)
        textView.setSelectedRange(NSRange(location: location, length: min(selection.length, limit - location)))
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
