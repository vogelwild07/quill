import QuillModel
import QuillSync
import SwiftData
import SwiftUI

/// Konflikte einer Seite mit Wahl je Fassung (11.6, ADR-029). Jede Fassung nennt ihr
/// Gerät aus `devices/` im Ordner. Gewählt wird nur, wenn der Sync an und nicht
/// pausiert ist. `blockID` beschränkt die Liste auf einen Block (Zeichen am Rand).
struct ConflictListView: View {
    let pageID: UUID
    let sync: SyncController
    var blockID: UUID?
    /// Text eines Blocks der Seite, für die Überschrift eines Block-Konflikts.
    var blockText: (UUID) -> String? = { _ in nil }
    /// Titel einer Seite, für Konflikte beim Ort.
    var pageTitle: (UUID) -> String? = { _ in nil }

    private var conflicts: [PageConflict] {
        let all = sync.conflicts(onPage: pageID)
        guard let blockID else { return all }
        return all.filter { !$0.isPageField && $0.conflict.objectID == blockID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Zwei Fassungen nach dem Abgleich", bundle: .module)
                .font(.headline)
            if conflicts.isEmpty {
                Text("Keine offenen Konflikte.", bundle: .module)
                    .foregroundStyle(.secondary)
            }
            ForEach(conflicts) { conflict in
                VStack(alignment: .leading, spacing: 6) {
                    Text(heading(conflict))
                        .font(.subheadline.weight(.semibold))
                    ForEach(conflict.conflict.versions, id: \.value) { version in
                        row(version, in: conflict)
                    }
                }
            }
            if !sync.canChoose {
                Label(String(localized: "Zum Wählen Sync fortsetzen.", bundle: .module), systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("conflict.paused")
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conflict.list")
    }

    private func row(_ version: ConflictVersion, in conflict: PageConflict) -> some View {
        let value = ConflictLabel.value(version, in: conflict, pageTitle: pageTitle)
        let device = sync.deviceName(version.device)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: value)
                    .lineLimit(2)
                Text("von \(device)", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(String(localized: "Wählen", bundle: .module)) {
                Task { await sync.choose(conflict.choice(version)) }
            }
            .disabled(!sync.canChoose)
            .accessibilityLabel(String(localized: "\(value) von \(device) wählen", bundle: .module))
            .accessibilityIdentifier("conflict.choose")
        }
    }

    private func heading(_ conflict: PageConflict) -> String {
        let field = ConflictLabel.field(conflict)
        guard !conflict.isPageField, blockID == nil, conflict.conflict.field != nil,
              let text = blockText(conflict.conflict.objectID)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return field }
        return String(localized: "\(field) · „\(String(text.prefix(40)))“", bundle: .module)
    }
}

/// Popover zu einem wiederhergestellten Block: was passiert ist, und die Marke entfernen.
struct RestoredBlockView: View {
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wiederhergestellt nach dem Abgleich", bundle: .module)
                .font(.headline)
            Text("Ein anderes Gerät hat diesen Block gelöscht oder anders geändert, während er hier bearbeitet wurde. Quill hat ihn behalten, damit nichts verloren geht.", bundle: .module)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            Button(String(localized: "Markierung entfernen", bundle: .module), action: clear)
                .accessibilityIdentifier("restored.clear")
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}

/// Hinweise des Sync im Seitenkopf: offene Konflikte der Seite und die Marke
/// „wiederhergestellt“ der Seite selbst (Papierkorb gegen Bearbeiten).
struct PageSyncNotice: View {
    let pageID: UUID
    let sync: SyncController?
    let isRestored: Bool
    let clearRestored: () -> Void
    let trash: () -> Void
    var blockText: (UUID) -> String? = { _ in nil }
    var pageTitle: (UUID) -> String? = { _ in nil }

    @State private var showsConflicts = false

    var body: some View {
        let count = sync?.conflicts(onPage: pageID).count ?? 0
        if count > 0 || isRestored {
            VStack(alignment: .leading, spacing: 8) {
                if count > 0, let sync {
                    HStack(spacing: 10) {
                        Label(String(localized: "\(count) Stellen mit zwei Fassungen", bundle: .module), systemImage: "square.on.square")
                        Button(String(localized: "Wählen …", bundle: .module)) { showsConflicts = true }
                            .accessibilityIdentifier("detail.conflicts")
                            .popover(isPresented: $showsConflicts, arrowEdge: .bottom) {
                                ConflictListView(pageID: pageID, sync: sync, blockText: blockText, pageTitle: pageTitle)
                            }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("detail.conflictNotice")
                }
                if isRestored {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            String(localized: "Hier behalten: Auf einem anderen Gerät kam die Seite in den Papierkorb, hier wurde sie bearbeitet.", bundle: .module),
                            systemImage: "arrow.uturn.backward.circle"
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(String(localized: "Markierung entfernen", bundle: .module), action: clearRestored)
                                .accessibilityIdentifier("detail.restored.clear")
                            Button(String(localized: "In den Papierkorb", bundle: .module), action: trash)
                                .accessibilityIdentifier("detail.restored.trash")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("detail.restoredNotice")
                }
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        }
    }
}
