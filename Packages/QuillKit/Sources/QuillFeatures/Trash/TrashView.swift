import QuillModel
import SwiftData
import SwiftUI

/// Papierkorb eines Fensters (ADR-017): Liste mit Pfad, Datum und den ersten Worten,
/// Wiederherstellen (mit Undo) und endgültig Löschen (mit Rückfrage und Backup).
struct TrashView: View {
    let restore: (UUID) -> Void

    @Environment(\.quillPersistence) private var persistence
    @Query(filter: #Predicate<Page> { $0.trashedAt != nil }, sort: \Page.trashedAt, order: .reverse)
    private var pages: [Page]
    @State private var selection: Set<UUID> = []
    @State private var pendingDeletion: Deletion?
    @State private var failure: String?
    /// Beim Öffnen bekommt die Liste den Fokus, damit ⌫ und die Pfeiltasten wirken;
    /// sonst bliebe er in der Sidebar.
    @FocusState private var isListFocused: Bool

    /// Was nach der Rückfrage endgültig gelöscht wird.
    enum Deletion: Hashable {
        case pages([UUID])
        case all
    }

    var body: some View {
        let entries = pages.map(TrashedPage.init)
        VStack(alignment: .leading, spacing: 0) {
            header(isEmpty: entries.isEmpty)
            if let failure {
                failureBanner(failure)
            }
            Divider()
            if entries.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Der Papierkorb ist leer", bundle: .module), systemImage: "trash")
                }
                .accessibilityIdentifier("trash.emptyState")
            } else {
                List(selection: $selection) {
                    ForEach(entries) { entry in
                        TrashRow(entry: entry).tag(entry.id)
                    }
                }
                .accessibilityLabel(String(localized: "Seiten im Papierkorb", bundle: .module))
                .accessibilityIdentifier("trash.list")
                .focused($isListFocused)
                .onAppear { isListFocused = true }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    Button(String(localized: "Wiederherstellen", bundle: .module)) { ids.forEach(restore) }
                    Button(String(localized: "Endgültig löschen …", bundle: .module), role: .destructive) {
                        pendingDeletion = .pages(Array(ids))
                    }
                }
                .onDeleteCommand {
                    if !selection.isEmpty { pendingDeletion = .pages(Array(selection)) }
                }
            }
        }
        .navigationTitle(String(localized: "Papierkorb", bundle: .module))
        .toolbar {
            ToolbarItemGroup {
                Button(String(localized: "Wiederherstellen", bundle: .module), systemImage: "arrow.uturn.backward") {
                    selection.forEach(restore)
                }
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("trash.restore")
                Button(String(localized: "Endgültig löschen …", bundle: .module), systemImage: "trash.slash") {
                    pendingDeletion = .pages(Array(selection))
                }
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("trash.delete")
            }
        }
        .alert(
            confirmationTitle(entries),
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { deletion in
            Button(String(localized: "Endgültig löschen", bundle: .module), role: .destructive) { delete(deletion) }
            Button(String(localized: "Abbrechen", bundle: .module), role: .cancel) {}
        } message: { _ in
            Text("Das lässt sich nicht rückgängig machen. Unterseiten werden mitgelöscht.", bundle: .module)
        }
    }

    /// Nicht modal (design.md: Dialoge nur für „Endgültig löschen“), wie der
    /// Hinweis beim Speichern.
    private func failureBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Löschen fehlgeschlagen", bundle: .module).fontWeight(.medium)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "Ausblenden", bundle: .module), systemImage: "xmark") { failure = nil }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trash.failure")
    }

    private func header(isEmpty: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Papierkorb", bundle: .module).font(.title2.weight(.semibold))
                Text("Seiten werden nach \(QuillPersistence.trashRetentionDays) Tagen endgültig gelöscht.", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "Papierkorb leeren …", bundle: .module)) { pendingDeletion = .all }
                .disabled(isEmpty)
                .accessibilityIdentifier("trash.empty")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func confirmationTitle(_ entries: [TrashedPage]) -> String {
        switch pendingDeletion {
        case .pages(let ids) where ids.count == 1:
            let name = PageLabel.title(entries.first { $0.id == ids[0] }?.title ?? "")
            return String(localized: "„\(name)“ endgültig löschen?", bundle: .module)
        case .pages(let ids):
            return String(localized: "\(ids.count) Seiten endgültig löschen?", bundle: .module)
        case .all, nil:
            return String(localized: "Papierkorb leeren?", bundle: .module)
        }
    }

    private func delete(_ deletion: Deletion) {
        guard let persistence else { return }
        failure = nil
        Task {
            do {
                switch deletion {
                case .pages(let ids):
                    try await persistence.deletePermanently(ids)
                case .all:
                    try await persistence.emptyTrash()
                }
                selection = []
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

/// Eine Zeile: Icon und Titel, darunter die ersten Worte, dann Pfad und Datum.
private struct TrashRow: View {
    let entry: TrashedPage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            PageIconView(icon: entry.icon)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(PageLabel.title(entry.title))
                    .fontWeight(.medium)
                if !entry.preview.isEmpty {
                    Text(entry.preview)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trash.row")
    }

    private var details: String {
        let date = entry.trashedAt.formatted(.relative(presentation: .named))
        let path = PageLabel.path(entry.path)
        return path.isEmpty ? date : "\(path) · \(date)"
    }
}
