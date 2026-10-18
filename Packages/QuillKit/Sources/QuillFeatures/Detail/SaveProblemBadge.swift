import SwiftUI

/// Dezenter Hinweis oben in der Seite, solange Änderungen nicht gespeichert werden
/// konnten. Die Bridge versucht es weiter; der Hinweis verschwindet danach von selbst.
struct SaveProblemBadge: View {
    let error: any Error

    var body: some View {
        Label(String(localized: "Nicht gespeichert", bundle: .module), systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: .capsule)
            .help(String(
                localized: "Änderungen konnten nicht gespeichert werden. Quill versucht es automatisch erneut.\n\(error.localizedDescription)",
                bundle: .module
            ))
            .accessibilityIdentifier("detail.saveProblem")
    }
}
