import QuillEditor
import QuillFeatures
import SwiftUI

@main
struct QuillApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            switch appDelegate.persistence {
            case .success(let persistence):
                RootView()
                    .modelContainer(persistence.container)
                    .environment(\.pageStore, persistence.store)
                    .environment(\.quillPersistence, persistence)
            case .failure(let error):
                PersistenceErrorView(error: error)
            }
        }
        .commands {
            QuillCommands(persistence: try? appDelegate.persistence.get())
        }

        Settings {
            SettingsView()
        }
    }
}

/// Öffnet die Datenbank vor dem ersten Fenster und sichert beim Beenden.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Vor `persistence`: Eigenschaften werden in dieser Reihenfolge initialisiert, so
    /// zählt das Öffnen der Datenbank zum gemessenen Start (`docs/performance.md`).
    private let launchSignpost: Void = QuillSignposts.beginLaunch()
    #if QUILL_PROFILING
    private let profilingReset: Void = ProfilingSeed.resetStoreIfRequested()
    #endif
    let persistence = Result { try QuillPersistence.open() }
    /// Vor dem ersten Fenster, damit der erste Editor schon im gewählten Theme zeichnet.
    private let editorTheme: Void = EditorThemeSetup.configure()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if QUILL_PROFILING
        if let persistence = try? persistence.get() {
            ProfilingSeed.seedAndQuit(persistence)
        }
        #endif
        #if DEBUG
        TestWindowSize.applyToFirstWindow()
        #endif
    }

    /// Speichert offene Änderungen aller Editoren, bevor die App endet (und vor dem Backup).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard EditorPersistenceBridge.hasAnyUnsavedChanges else { return .terminateNow }
        Task {
            let terminate = await QuitGuard.shouldTerminate()
            // Abgebrochen: Ein vorgemerktes Backup nicht unbemerkt beim nächsten Start einspielen.
            if !terminate { try? persistence.get().quitWasCancelled() }
            sender.reply(toApplicationShouldTerminate: terminate)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? persistence.get().backupOnQuit()
    }
}
