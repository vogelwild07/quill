import QuillModel
import SwiftUI

/// Wird gezeigt, wenn sich die Datenbank nicht öffnen lässt. Es wird bewusst
/// nicht auf einen leeren Speicher ausgewichen, damit nichts überschrieben wird.
public struct PersistenceErrorView: View {
    let error: any Error

    public init(error: any Error) {
        self.error = error
    }

    public var body: some View {
        ContentUnavailableView {
            // Titel in primary wie in `EmptyStateView`.
            Label {
                Text("Daten konnten nicht geöffnet werden", bundle: .module).foregroundStyle(.primary)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        } description: {
            VStack(spacing: 8) {
                Text("Quill hat nichts verändert. Deine Backups liegen unter „Application Support/Quill/Backups“.",
                     bundle: .module)
                Text(Self.detail(for: error))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }

    /// Fehler beim Vorbereiten des Stores (ADR-019) als lokalisierter Satz, andere
    /// technisch, wie das System sie beschreibt.
    static func detail(for error: any Error) -> String {
        guard let error = error as? StoreLayoutError else { return String(describing: error) }
        return switch error {
        case .locked:
            String(localized: "Eine andere Quill-Instanz richtet gerade die Datenbank ein.", bundle: .module)
        case .lockFailed(let reason):
            String(localized: "Sperre nicht möglich: \(reason)", bundle: .module)
        case .moveConflict(let path):
            String(localized: "Umzug angehalten, im Ziel liegt schon: \(path)", bundle: .module)
        case .leftover(let path):
            String(localized: "Unvollständiger Vorgang, Dateien liegen in: \(path)", bundle: .module)
        }
    }
}
