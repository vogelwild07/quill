import QuillEditor
import QuillEditorCore
import QuillFeatures
import SwiftUI

@main
struct QuillApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            switch appDelegate.persistence {
            case .success(let persistence)?:
                RootView()
                    .modelContainer(persistence.container)
                    .environment(\.pageStore, persistence.store)
                    .environment(\.quillPersistence, persistence)
            case .failure(let error)?:
                PersistenceErrorView(error: error)
            case nil:
                // Die Rückfrage vor einer Migration läuft (`applicationDidFinishLaunching`).
                Color.clear
            }
        }
        .commands {
            QuillCommands(persistence: try? appDelegate.persistence?.get())
        }

        Settings {
            SettingsView(persistence: try? appDelegate.persistence?.get())
        }
    }
}

/// Öffnet die Datenbank vor dem ersten Fenster und sichert beim Beenden.
///
/// Steht eine Migration an, öffnet sie erst nach dem Start, mit Rückfrage (Phase 11.2):
/// Ein Dialog vor dem Start wäre für Bedienungshilfen nicht erreichbar.
@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Vor `persistence`: Eigenschaften werden in dieser Reihenfolge initialisiert, so
    /// zählt das Öffnen der Datenbank zum gemessenen Start (`docs/performance.md`).
    private let launchSignpost: Void = QuillSignposts.beginLaunch()
    #if QUILL_PROFILING
    private let profilingReset: Void = ProfilingSeed.resetStoreIfRequested()
    #endif
    /// `nil`, solange die Rückfrage vor einer Migration aussteht.
    private(set) var persistence: Result<QuillPersistence, any Error>? = AppDelegate.openUnlessMigrationNeedsAnswer()
    /// Vor dem ersten Fenster, damit der erste Editor schon im gewählten Theme zeichnet.
    private let editorTheme: Void = EditorThemeSetup.configure()

    /// Öffnet sofort, außer eine Migration braucht eine Antwort; dann `nil`.
    private static func openUnlessMigrationNeedsAnswer() -> Result<QuillPersistence, any Error>? {
        let result = Result { try QuillPersistence.open { _, _ in .later } }
        if case .failure(QuillPersistence.OpenError.migrationDeferred) = result { return nil }
        return result
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if persistence == nil {
            let result = Result { try QuillPersistence.open(confirmMigration: MigrationPrompt.ask) }
            if case .failure(QuillPersistence.OpenError.migrationDeclined) = result {
                // Nichts wurde verändert; ohne Fenster beenden.
                NSApp.terminate(nil)
                return
            }
            persistence = result
        }
        #if QUILL_PROFILING
        if let persistence = try? persistence?.get() {
            ProfilingSeed.seedAndQuit(persistence)
        }
        #endif
        // Geschichte für die Zeitreise, auch ohne Sync (ADR-031).
        try? persistence?.get().history.start()
        // Gleicht nur ab, wenn der Nutzer den Sync eingeschaltet hat (ADR-029).
        try? persistence?.get().sync.start()
        #if DEBUG
        TestWindowSize.applyToFirstWindow()
        TestWindowScreen.start()
        #endif
    }

    /// Speichert offene Änderungen aller Editoren, bevor die App endet (und vor dem Backup),
    /// und zeichnet danach die Geschichte auf, die noch wartet (ADR-031).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let history = try? persistence?.get().history
        guard EditorPersistenceBridge.hasAnyUnsavedChanges || history?.hasUnrecordedSaves == true else { return .terminateNow }
        Task {
            let terminate = await QuitGuard.shouldTerminate()
            // Abgebrochen: Ein vorgemerktes Backup nicht unbemerkt beim nächsten Start einspielen.
            if !terminate { try? persistence?.get().quitWasCancelled() }
            if terminate { await history?.flush() }
            sender.reply(toApplicationShouldTerminate: terminate)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? persistence?.get().backupOnQuit()
    }
}
