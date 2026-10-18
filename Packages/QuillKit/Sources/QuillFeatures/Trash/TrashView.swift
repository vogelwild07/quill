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
            Divider()
            if entries.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Der Papierkorb ist leer", bundle: .module), systemImage: "trash")
                }
            } else {
                List(selection: $selection) {
                    ForEach(entries) { entry in
                        TrashRow(entry: entry).tag(entry.id)
                    }
                }
                .accessibilityIdentifier("trash.list")
                .focused($isListFocused)
                .onAppear { isListFocused = true }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    Button(String(localized: "Wiederherstellen", bundle: .module)) { ids.forEach(restore) }
                    Button(String(localized: "Endgültig löschen …", bundle: .module), role: .destructive) {
                        pendingDeletion = .pages(Array(ids))
                    }
                } primaryAction: { ids in
                    ids.forEach(restore)
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
        .alert(
            String(localized: "Löschen fehlgeschlagen", bundle: .module),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button(String(localized: "OK", bundle: .module)) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func header(isEmpty: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Papierkorb", bundle: .module).font(.title2.weight(.semibold))
                Text("Seiten werden nach 30 Tagen endgültig gelöscht.", bundle: .module)
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
            let title = entries.first { $0.id == ids[0] }?.title ?? ""
            let name = title.isEmpty ? String(localized: "Ohne Titel", bundle: .module) : title
            return String(localized: "„\(name)“ endgültig löschen?", bundle: .module)
        case .pages(let ids):
            return String(localized: "\(ids.count) Seiten endgültig löschen?", bundle: .module)
        case .all, nil:
            return String(localized: "Papierkorb leeren?", bundle: .module)
        }
    }

    private func delete(_ deletion: Deletion) {
        guard let persistence else { return }
        Task {
            do {
                switch deletion {
                case .pages(let ids):
                    for id in ids { try await persistence.deletePermanently(id) }
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
            Text(entry.icon ?? "📄")
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? String(localized: "Ohne Titel", bundle: .module) : entry.title)
                    .fontWeight(.medium)
                if !entry.preview.isEmpty {
                    Text(entry.preview)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trash.row")
    }

    private var details: String {
        let date = entry.trashedAt.formatted(.relative(presentation: .named))
        let path = entry.path.map { $0.isEmpty ? String(localized: "Ohne Titel", bundle: .module) : $0 }.joined(separator: " › ")
        return path.isEmpty ? date : "\(path) · \(date)"
    }
}
