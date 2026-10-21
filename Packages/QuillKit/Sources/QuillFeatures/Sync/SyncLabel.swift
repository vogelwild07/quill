import Foundation
import QuillSync

/// Texte zum Sync für Meldungen.
enum SyncLabel {
    static func enableMessage(for error: any Error) -> String {
        switch error {
        case SyncController.EnableError.folderNotEmpty:
            String(localized: "Im gewählten Ordner liegen schon Quill-Daten. Zum Neubeginnen braucht Quill einen leeren Ordner.", bundle: .module)
        case SyncController.EnableError.sameAsPreviousFolder:
            String(localized: "Das ist der bisherige Ordner. Zum Neubeginnen wähle einen anderen, leeren Ordner; mit dem bisherigen führt Quill zusammen.", bundle: .module)
        case SyncController.EnableError.noPreviousFolder:
            String(localized: "Den bisherigen Ordner gibt es nicht mehr oder Quill darf ihn nicht öffnen.", bundle: .module)
        default:
            String(localized: "Der Sync wurde nicht eingeschaltet: \(error.localizedDescription)", bundle: .module)
        }
    }

    /// Eine Lücke im Ordner (`SyncGap`): welche Seite, welches Gerät, seit wann.
    /// `pageTitle` ist `nil` für den Seitenbaum.
    static func gap(_ gap: SyncGap, device: String, pageTitle: String?) -> String {
        let since = gap.since.formatted(date: .abbreviated, time: .shortened)
        guard let pageTitle else {
            return String(localized: "Seitenbaum von „\(device)“: Dateien fehlen seit \(since).", bundle: .module)
        }
        return String(localized: "„\(PageLabel.title(pageTitle))“ von „\(device)“: Dateien fehlen seit \(since).", bundle: .module)
    }

    static func failureMessage(for error: any Error) -> String {
        switch error {
        case SyncFailure.folderMissing:
            String(localized: "Im Ordner fehlt „Quill/quill.json“. Wurde der Ordner verschoben oder gelöscht?", bundle: .module)
        case SyncFailure.waitingForDownload:
            String(localized: "Wartet, bis der Ordner geladen ist.", bundle: .module)
        case SyncFailure.newerFormat:
            String(localized: "Der Ordner stammt von einer neueren Quill-Version. Bitte Quill aktualisieren.", bundle: .module)
        case SyncFailure.unreadableManifest:
            String(localized: "„Quill/quill.json“ ist unlesbar.", bundle: .module)
        default:
            String(localized: "Abgleich gescheitert: \(error.localizedDescription)", bundle: .module)
        }
    }
}
