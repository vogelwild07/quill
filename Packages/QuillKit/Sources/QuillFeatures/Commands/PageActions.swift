import SwiftUI

/// Befehle des fokussierten Fensters für die Menüleiste.
public struct PageActions {
    /// Ausgewählte Seite des Fensters.
    public var selection: UUID?
    /// Ob die ausgewählte Seite ein Favorit ist.
    public var isFavorite: Bool
    /// „Schnell öffnen“ ist offen; ⌘↩ gehört dann dem Panel (neuer Tab).
    public var isQuickOpenShown: Bool
    var newPage: @MainActor () -> Void
    var newSubpage: @MainActor () -> Void
    var rename: @MainActor () -> Void
    var quickOpen: @MainActor () -> Void
    var trash: @MainActor () -> Void
    var toggleFavorite: @MainActor () -> Void
    var openInTab: @MainActor () -> Void
    var openInWindow: @MainActor () -> Void
}

extension FocusedValues {
    @Entry public var pageActions: PageActions?
}
