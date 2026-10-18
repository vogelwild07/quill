import SwiftUI

/// Befehle des fokussierten Fensters für die Menüleiste.
public struct PageActions {
    /// Ausgewählte Seite des Fensters.
    public var selection: UUID?
    var newPage: @MainActor () -> Void
    var newSubpage: @MainActor () -> Void
    var rename: @MainActor () -> Void
    var trash: @MainActor () -> Void
    var openInTab: @MainActor () -> Void
    var openInWindow: @MainActor () -> Void
}

extension FocusedValues {
    @Entry public var pageActions: PageActions?
}
