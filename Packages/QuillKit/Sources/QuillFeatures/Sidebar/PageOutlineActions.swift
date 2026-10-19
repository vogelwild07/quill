import Foundation
import QuillModel

/// Aktionen, die die Sidebar auslöst. Bezugsseite ist die angeklickte, nicht
/// zwingend die ausgewählte Seite.
///
/// Referenztyp: `RootView` legt ihn einmal an und setzt die Closures neu, wenn sich
/// Store oder Undo-Manager ändern. So bleibt `SidebarView` bei einem Seitenwechsel gleich, und
/// SwiftUI baut den Seitenbaum nicht neu auf (docs/performance.md). Closures als
/// Werte würden jede `SidebarView` als geändert erscheinen lassen.
@MainActor
final class PageOutlineActions {
    var create: (_ parentID: UUID?) -> Void = { _ in }
    var rename: (_ id: UUID, _ title: String, _ oldTitle: String) -> Void = { _, _, _ in }
    var move: (_ id: UUID, _ parentID: UUID?, _ position: SiblingPosition) -> Void = { _, _, _ in }
    var trash: (_ id: UUID) -> Void = { _ in }
    var setFavorite: (_ id: UUID, _ isFavorite: Bool, _ position: SiblingPosition) -> Void = { _, _, _ in }
    var moveFavorite: (_ id: UUID, _ position: SiblingPosition) -> Void = { _, _ in }
    var openInTab: (_ id: UUID) -> Void = { _ in }
    var openInWindow: (_ id: UUID) -> Void = { _ in }
    var export: (_ id: UUID) -> Void = { _ in }
    /// „Schnell öffnen“ (⌘O).
    var search: () -> Void = {}
    /// Tab aus der Sidebar: Fokus in Titel oder Editor der ausgewählten Seite.
    var focusPage: (_ target: PageFocusTarget) -> Void = { _ in }
}
