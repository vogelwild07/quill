import Foundation
import Observation

/// Ausgewählte Seite eines Fensters. `RootView` hält genau eine Instanz.
///
/// Referenztyp statt `Binding<UUID?>`: Ein Binding trägt den aktuellen Wert mit,
/// jede Auswahl ließe `SidebarView` als geändert gelten und den Seitenbaum aus allen
/// Seiten neu bauen (docs/performance.md). Die Outline liest `pageID` in
/// `updateNSView`; SwiftUI rechnet das `SidebarView` zu. Ein Klick in die Sidebar baut
/// den Baum daher nicht neu, eine Auswahl von außen (⌘O, Löschen) einmal.
@MainActor
@Observable
final class PageSelection {
    var pageID: UUID?
}
