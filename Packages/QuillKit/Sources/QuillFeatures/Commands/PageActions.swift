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
    var exportPage: @MainActor () -> Void
    /// „Zusammenfassen …“ (16.2, ADR-032); im Menü nur mit bereitem Modell.
    var summarize: @MainActor () -> Void
    /// „To-dos vorschlagen …“ (16.3, ADR-032); im Menü nur mit bereitem Modell.
    var suggestTodos: @MainActor () -> Void
    /// „Verwandte Seiten …“ (16.5, ADR-032); im Menü nur mit bereitem Modell.
    var relatedPages: @MainActor () -> Void
    /// „Frag deine Notizen …“ (16.4, ADR-032); im Menü nur mit bereitem Modell.
    var askNotes: @MainActor () -> Void
    /// „Erinnerung …“ für das To-do an der Einfügemarke (15.4, ADR-033).
    var remind: @MainActor () -> Void
    /// „Heute“: Tagesseite öffnen (15.5, ADR-033).
    var openToday: @MainActor () -> Void
    /// „Heutige Termine einfügen“ an der Einfügemarke (15.5, ADR-033).
    var insertTodayEvents: @MainActor () -> Void
    /// „Sprachnotiz …“ an der Einfügemarke (17.2, ADR-034).
    var voiceNote: @MainActor () -> Void
}

/// Befehle des fokussierten Fensters, die nicht von einer Seite abhängen.
public struct WindowActions {
    /// Öffnet das Sheet „Backup wiederherstellen“ in diesem Fenster.
    var restoreBackup: @MainActor () -> Void
}

extension FocusedValues {
    @Entry public var pageActions: PageActions?
    @Entry public var windowActions: WindowActions?
    /// Das Fenster zeigt einen Editor im Lesemodus (Zeitreise): Menü „Format“ gesperrt.
    @Entry public var readOnlyEditor: Bool?
}
