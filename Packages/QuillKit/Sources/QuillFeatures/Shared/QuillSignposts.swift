#if canImport(AppKit)
import AppKit
import OSLog

/// Messpunkte für Instruments („Points of Interest“) und die Performance-UI-Tests
/// (`docs/performance.md`). Ohne Aufzeichnung kosten sie praktisch nichts und ändern
/// kein Verhalten.
///
/// Jedes Intervall endet erst, wenn das Ergebnis gezeichnet ist: nach dem nächsten
/// Commit von Core Animation (`afterNextCommit`).
@MainActor
public enum QuillSignposts {
    public static let subsystem = "de.vogel.quill"
    public static let category = OSLog.Category.pointsOfInterest

    /// Namen der Intervalle; die UI-Tests nutzen dieselben Zeichenketten.
    public enum Name {
        /// Start des App-Delegates bis zur ersten gezeichneten Sidebar.
        public static let launch: StaticString = "launch"
        /// Erster Aufbau der Sidebar: Seitenbaum berechnen, laden, zeichnen.
        public static let sidebarLoad: StaticString = "sidebarLoad"
        /// Neue Seite (⌘N oder „Neue Seite“) bis zur neu geladenen, gezeichneten Sidebar:
        /// Speichern, Abfrage, Seitenbaum, Neuladen der Outline.
        public static let sidebarReload: StaticString = "sidebarReload"
        /// Klick auf eine Seite in der Sidebar bis zum gezeichneten Editor.
        public static let pageSwitch: StaticString = "pageSwitch"
    }

    static let signposter = OSSignposter(subsystem: subsystem, category: category)

    private static var launch: OSSignpostIntervalState?
    private static var sidebarLoad: OSSignpostIntervalState?
    private static var hasLoadedSidebar = false
    private static var sidebarReload: OSSignpostIntervalState?
    private static var pageSwitch: OSSignpostIntervalState?

    // MARK: Start

    public static func beginLaunch() {
        launch = signposter.beginInterval(Name.launch)
    }

    /// Im ersten `body` der Sidebar, vor dem Berechnen des Seitenbaums.
    static func beginSidebarLoadIfNeeded() {
        guard !hasLoadedSidebar, sidebarLoad == nil else { return }
        sidebarLoad = signposter.beginInterval(Name.sidebarLoad)
    }

    /// Vor dem Anlegen einer neuen Seite. Läuft schon eins, zählt das erste.
    static func beginSidebarReload() {
        guard hasLoadedSidebar, sidebarReload == nil else { return }
        sidebarReload = signposter.beginInterval(Name.sidebarReload)
    }

    /// Anlegen gescheitert: Das Intervall endet nicht, damit kein späteres Neuladen
    /// einen falschen Wert liefert.
    static func cancelSidebarReload() {
        sidebarReload = nil
    }

    /// Nach jedem Neuladen der Outline. Das erste beendet `sidebarLoad` und `launch`,
    /// ein späteres ein begonnenes `sidebarReload`.
    static func sidebarDidReload() {
        if !hasLoadedSidebar {
            hasLoadedSidebar = true
            let load = sidebarLoad
            let launch = launch
            sidebarLoad = nil
            Self.launch = nil
            afterNextCommit {
                if let load { signposter.endInterval(Name.sidebarLoad, load) }
                if let launch { signposter.endInterval(Name.launch, launch) }
            }
            return
        }
        guard let reload = sidebarReload else { return }
        sidebarReload = nil
        afterNextCommit { signposter.endInterval(Name.sidebarReload, reload) }
    }

    // MARK: Seitenwechsel

    /// Der Nutzer hat in der Sidebar eine andere Seite gewählt.
    static func beginPageSwitch() {
        pageSwitch = signposter.beginInterval(Name.pageSwitch)
    }

    /// Der Editor der neuen Seite ist geladen. Ohne begonnenen Wechsel (⌘N, Schnell
    /// öffnen, neues Fenster) passiert nichts.
    static func pageDidLoad() {
        guard let state = pageSwitch else { return }
        pageSwitch = nil
        afterNextCommit { signposter.endInterval(Name.pageSwitch, state) }
    }

    // MARK: Hilfen

    /// Führt `block` einmal aus, wenn die Hauptschleife das nächste Mal wartet, nach dem
    /// Commit von Core Animation (Reihenfolge 2 000 000), also nach Layout und Zeichnen.
    private static func afterNextCommit(_ block: @escaping @MainActor () -> Void) {
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, false, 2_000_001
        ) { _, _ in
            MainActor.assumeIsolated { block() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}
#endif
