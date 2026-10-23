import AppIntents
import QuillFeatures

/// Nimmt die Kurzbefehle aus QuillKit in die App auf (ADR-033).
struct QuillAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [QuillFeaturesIntents.self]
    }
}

/// Siri-Sätze; das System liest sie nur aus dem App-Target.
struct QuillShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewPageIntent(),
            phrases: ["Neue Seite in \(.applicationName)", "Neue Seite mit \(.applicationName) anlegen"],
            shortTitle: "Neue Seite",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: AddToPageIntent(),
            phrases: ["Zu \(\.$page) in \(.applicationName) hinzufügen", "In \(.applicationName) zu \(\.$page) hinzufügen"],
            shortTitle: "Zu Seite hinzufügen",
            systemImageName: "text.append"
        )
        AppShortcut(
            intent: OpenPageIntent(),
            phrases: ["\(\.$target) in \(.applicationName) öffnen", "Öffne \(\.$target) in \(.applicationName)"],
            shortTitle: "Seite öffnen",
            systemImageName: "doc.text"
        )
    }
}
