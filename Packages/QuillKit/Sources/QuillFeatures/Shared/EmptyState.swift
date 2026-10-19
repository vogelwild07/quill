import SwiftUI

/// Leerzustände nach HIG: Symbol, Titel, ein Satz Erklärung, wo es passt ein Knopf
/// (docs/design.md). Ein Katalog, damit `EmptyStateSnapshotTests` jeden Fall hell
/// und dunkel prüft.
enum EmptyState: CaseIterable {
    /// Detailbereich ohne ausgewählte Seite.
    case noSelection
    /// Sidebar und „Schnell öffnen“ vor der ersten Seite.
    case noPages
    /// Ausgewählte Seite gibt es nicht mehr.
    case pageNotFound
    case emptyTrash
    case noBackups
    /// „Schnell öffnen“ ohne Treffer.
    case noResults

    var title: String {
        switch self {
        case .noSelection: String(localized: "Keine Seite ausgewählt", bundle: .module)
        case .noPages: String(localized: "Noch keine Seiten", bundle: .module)
        case .pageNotFound: String(localized: "Seite nicht gefunden", bundle: .module)
        case .emptyTrash: String(localized: "Der Papierkorb ist leer", bundle: .module)
        case .noBackups: String(localized: "Noch keine Backups", bundle: .module)
        case .noResults: String(localized: "Keine Treffer", bundle: .module)
        }
    }

    var message: String {
        switch self {
        case .noSelection: String(localized: "Wähle links eine Seite oder lege eine neue an.", bundle: .module)
        case .noPages: String(localized: "Mit ⌘N legst du die erste Seite an.", bundle: .module)
        case .pageNotFound: String(localized: "Sie wurde gelöscht oder liegt im Papierkorb.", bundle: .module)
        case .emptyTrash: String(localized: "Gelöschte Seiten bleiben hier 30 Tage und lassen sich wiederherstellen.", bundle: .module)
        case .noBackups: String(localized: "Quill sichert die Daten beim Start und beim Beenden.", bundle: .module)
        case .noResults: String(localized: "Kein Seitentitel und kein Text passt zur Suche.", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
        case .noSelection: "doc.text"
        case .noPages: "doc.badge.plus"
        case .pageNotFound: "doc.questionmark"
        case .emptyTrash: "trash"
        case .noBackups: "clock.arrow.circlepath"
        case .noResults: "magnifyingglass"
        }
    }
}

/// Ein Leerzustand als `ContentUnavailableView`, optional mit Knopf. Identifier
/// `<id>.title`, `<id>.message`, `<id>.action`; ein Identifier außen ginge an alle
/// Kinder. Der Titel steht
/// in primary: Im Systemstil ist er hell nur 3,1:1 kontrastreich (WCAG verlangt
/// 4,5:1); Symbol und Erklärung bleiben grau.
struct EmptyStateView: View {
    let state: EmptyState
    let id: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ state: EmptyState, id: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.state = state
        self.id = id
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(state.title).foregroundStyle(.primary)
            } icon: {
                Image(systemName: state.systemImage)
            }
            .accessibilityIdentifier("\(id).title")
        } description: {
            Text(state.message)
                .accessibilityIdentifier("\(id).message")
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .accessibilityIdentifier("\(id).action")
            }
        }
    }
}
