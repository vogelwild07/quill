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
                Text(String(describing: error))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
