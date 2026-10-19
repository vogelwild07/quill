#if canImport(AppKit)
import AppKit

/// Tastaturfokus zwischen den Bereichen eines Fensters (Sidebar, Titel, Editor).
/// Die Reihenfolge legt Quill selbst fest, statt der automatischen von AppKit zu
/// folgen: Die führte über das Titelfeld einer Sidebar-Zeile in deren Umbenennung.
///
/// Sidebar →Tab→ Titel →Tab→ Editor →⌃Tab→ Sidebar; rückwärts mit ⇧.
@MainActor
enum WindowFocus {
    /// Fokus in den Seitenbaum der Sidebar.
    @discardableResult
    static func sidebar(in window: NSWindow?) -> Bool {
        guard let window, let outline = window.contentView.flatMap(firstOutline(in:)) else { return false }
        return window.makeFirstResponder(outline)
    }

    private static func firstOutline(in view: NSView) -> PageOutlineTableView? {
        if let outline = view as? PageOutlineTableView { return outline }
        for subview in view.subviews {
            if let outline = firstOutline(in: subview) { return outline }
        }
        return nil
    }
}

/// Ziel, wenn der Fokus die Sidebar per Tab verlässt.
enum PageFocusTarget {
    /// Tab: Titel der ausgewählten Seite.
    case title
    /// ⇧Tab: Editor der ausgewählten Seite.
    case editor
}
#endif
