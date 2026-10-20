#if canImport(AppKit)
import SwiftUI
import UniformTypeIdentifiers

/// Nach einem eingespielten Backup (ADR-029): Der Sync wurde dafür ausgeschaltet;
/// zusammenführen, mit einem neuen Ordner neu beginnen oder aus lassen. Keine Wahl ist
/// Standard für Return: Zusammenführen bringt neuere Stände zurück, das soll bewusst
/// geschehen. Escape heißt „Später“. Der bisherige Ordner wird nie überschrieben.
struct SyncReconnectView: View {
    let sync: SyncController
    /// Nur UI-Tests: Ordner statt der Dateiauswahl für „Neu beginnen“.
    let testFolder: URL?
    let dismiss: () -> Void

    @State private var isChoosingFolder = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sync nach dem Backup", bundle: .module)
                .font(.headline)
            Text("Für das Backup hat Quill den Sync ausgeschaltet. Wie soll es weitergehen?", bundle: .module)
                .fixedSize(horizontal: false, vertical: true)

            choice(
                String(localized: "Zusammenführen", bundle: .module),
                detail: mergeDetail
            )
            choice(
                String(localized: "Neu beginnen mit neuem Ordner", bundle: .module),
                detail: String(localized: "Du wählst einen leeren Ordner; der Stand aus dem Backup kommt dorthin. Der bisherige Ordner bleibt unverändert, andere Macs müssen den neuen Ordner wählen.", bundle: .module)
            )
            choice(
                String(localized: "Später", bundle: .module),
                detail: String(localized: "Der Sync bleibt aus. Einschalten kannst du ihn jederzeit in den Einstellungen.", bundle: .module)
            )

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("syncReconnect.error")
            }

            HStack {
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button(String(localized: "Später", bundle: .module), role: .cancel) {
                    sync.declineReconnect()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("syncReconnect.later")
                Button(String(localized: "Neu beginnen …", bundle: .module)) { chooseFolder() }
                    .accessibilityIdentifier("syncReconnect.startOver")
                Button(String(localized: "Zusammenführen", bundle: .module)) { run(.merge) }
                    .disabled(sync.previousFolder == nil)
                    .accessibilityIdentifier("syncReconnect.merge")
            }
            .disabled(isWorking)
        }
        .padding(20)
        .frame(width: 480)
        .interactiveDismissDisabled()
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result { run(.startOver(folder)) }
        }
    }

    private var mergeDetail: String {
        let name = sync.previousFolder?.lastPathComponent ?? String(localized: "nicht erreichbar", bundle: .module)
        return String(localized: "Mit dem bisherigen Ordner „\(name)“. Neuere Stände aus dem Ordner kommen dabei zurück, auch solche, die das Backup zurückgesetzt hat.", bundle: .module)
    }

    private func choice(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.semibold)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func chooseFolder() {
        errorMessage = nil
        if let testFolder {
            run(.startOver(testFolder))
        } else {
            isChoosingFolder = true
        }
    }

    private func run(_ choice: SyncController.Reconnect) {
        errorMessage = nil
        isWorking = true
        Task {
            do {
                try await sync.reconnect(choice)
                dismiss()
                await sync.syncNow()
            } catch {
                errorMessage = SyncLabel.enableMessage(for: error)
            }
            isWorking = false
        }
    }
}

/// Unten in der Sidebar, nur wenn es etwas zu sagen gibt: Fortschritt beim Abgleich
/// (vor allem beim ersten, mit vielen Seiten) oder ein Problem. Ein Klick öffnet die
/// Einstellungen.
struct SyncSidebarStatus: View {
    /// Ab so vielen Seiten zeigt die Sidebar den Fortschritt; der Abgleich einer
    /// einzelnen geänderten Seite ließe die Zeile nur aufflackern.
    static let minimumPagesForProgress = 5

    let sync: SyncController

    var body: some View {
        if isVisible {
            SettingsLink {
                HStack(spacing: 6) {
                    if case .syncing(let progress) = sync.status, progress.total > 0 {
                        ProgressView(value: Double(progress.done), total: Double(progress.total))
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    SyncStatusText(sync: sync)
                        .font(.caption)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityLabel(String(localized: "Sync", bundle: .module))
            .accessibilityIdentifier("sidebar.syncStatus")
        }
    }

    private var isVisible: Bool {
        switch sync.status {
        case .syncing(let progress): progress.total >= Self.minimumPagesForProgress
        case .failed, .needsConfirmation: true
        case .off, .idle, .paused: false
        }
    }
}
#endif
