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
            case .failure(let error):
                PersistenceErrorView(error: error)
            }
        }
        .commands {
            QuillCommands(persistence: try? appDelegate.persistence.get())
        }
    }
}

/// Öffnet die Datenbank vor dem ersten Fenster und sichert beim Beenden.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let persistence = Result { try QuillPersistence.open() }

    func applicationWillTerminate(_ notification: Notification) {
        try? persistence.get().backupOnQuit()
    }
}
