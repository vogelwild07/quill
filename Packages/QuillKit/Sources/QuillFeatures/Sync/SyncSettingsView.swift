#if canImport(AppKit)
import QuillSync
import SwiftUI
import UniformTypeIdentifiers

/// Einstellungen › Sync (ADR-029): einschalten mit Ordner, Status mit Fortschritt,
/// pausieren, ausschalten. Der Sync bleibt aus, bis der Nutzer hier einen Ordner wählt.
struct SyncSettingsView: View {
    let sync: SyncController
    /// Nur UI-Tests: Ordner statt der Dateiauswahl.
    let testFolder: URL?

    @State private var isChoosingFolder = false
    @State private var isConfirmingOff = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if sync.isEnabled {
                connectedSection
                if let report = sync.lastReport {
                    SyncReportSection(report: report)
                }
                Section {
                    Button(String(localized: "Sync ausschalten …", bundle: .module), role: .destructive) { isConfirmingOff = true }
                        .accessibilityIdentifier("sync.turnOff")
                } footer: {
                    Text("Seiten und Ordner bleiben dabei unverändert.", bundle: .module)
                }
            } else {
                offSection
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("sync.error")
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result { enable(folder) }
        }
        .confirmationDialog(
            String(localized: "Sync ausschalten?", bundle: .module), isPresented: $isConfirmingOff
        ) {
            Button(String(localized: "Ausschalten", bundle: .module), role: .destructive) { sync.disable() }
                .accessibilityIdentifier("sync.turnOff.confirm")
        } message: {
            Text("Seiten und Ordner bleiben, wie sie sind. Wählst du denselben Ordner später wieder, führt Quill zusammen.", bundle: .module)
        }
    }

    // MARK: Aus

    private var offSection: some View {
        Section {
            Text("Quill gleicht deine Seiten über einen Ordner ab, zum Beispiel in iCloud Drive. Jeder Mac schreibt dort nur eigene Dateien, nichts wird überschrieben.", bundle: .module)
                .fixedSize(horizontal: false, vertical: true)
            Text("Vor dem Einschalten legt Quill ein Backup an. Der Sync ist neu und noch eine Beta.", bundle: .module)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let previous = sync.previousFolder {
                Text("Wählst du den bisherigen Ordner „\(previous.lastPathComponent)“ wieder, führt Quill zusammen. Mit einem anderen Ordner beginnt es dort neu.", bundle: .module)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button(String(localized: "Ordner wählen und einschalten …", bundle: .module)) { chooseFolder() }
                    .disabled(isWorking)
                    .accessibilityIdentifier("sync.enable")
            }
        } header: {
            Text("Sync ist aus", bundle: .module)
        }
    }

    // MARK: An

    private var connectedSection: some View {
        Section {
            LabeledContent(String(localized: "Ordner", bundle: .module)) {
                Text(sync.folder?.path(percentEncoded: false) ?? String(localized: "nicht erreichbar", bundle: .module))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            LabeledContent(String(localized: "Status", bundle: .module)) {
                SyncStatusText(sync: sync)
                    .accessibilityIdentifier("sync.status")
            }
            if case .syncing(let progress) = sync.status, progress.total > 0 {
                ProgressView(value: Double(progress.done), total: Double(progress.total))
                    .accessibilityLabel(String(localized: "Fortschritt des Abgleichs", bundle: .module))
            }
            if case .needsConfirmation(let folderID) = sync.status {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Im Ordner liegen schon Quill-Daten, etwa von einem anderen Mac. Quill führt sie erst zusammen, wenn du zustimmst; geschrieben wurde noch nichts.", bundle: .module)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button(String(localized: "Sync ausschalten", bundle: .module)) { sync.disable() }
                        Button(String(localized: "Zusammenführen", bundle: .module)) { Task { await sync.confirmFolder(folderID) } }
                            .accessibilityIdentifier("sync.confirmFolder")
                    }
                }
            }
            Toggle(isOn: Binding(get: { sync.status == .paused }, set: { pause($0) })) {
                Text("Sync pausieren", bundle: .module)
                Text("Quill schreibt nichts in den Ordner, bis du fortsetzt, auch nicht nach einem Neustart.", bundle: .module)
            }
            .accessibilityIdentifier("sync.pause")
            HStack {
                Spacer()
                Button(String(localized: "Jetzt abgleichen", bundle: .module)) { Task { await sync.syncNow() } }
                    .disabled(sync.status == .paused || sync.isSyncing)
                    .accessibilityIdentifier("sync.now")
            }
        } header: {
            Text("Sync ist an", bundle: .module)
        }
    }

    // MARK: Aktionen

    private func chooseFolder() {
        errorMessage = nil
        if let testFolder {
            enable(testFolder)
        } else {
            isChoosingFolder = true
        }
    }

    private func enable(_ folder: URL) {
        isWorking = true
        Task {
            do {
                try await sync.enable(folder: folder)
                await sync.syncNow()
            } catch {
                errorMessage = SyncLabel.enableMessage(for: error)
            }
            isWorking = false
        }
    }

    private func pause(_ paused: Bool) {
        if paused {
            sync.pause()
        } else {
            sync.resume()
            Task { await sync.syncNow() }
        }
    }
}

/// Ergebnis des letzten Abgleichs: nur, was der Nutzer wissen sollte.
private struct SyncReportSection: View {
    let report: SyncReport

    var body: some View {
        let conflicts = report.conflicts.values.reduce(0) { $0 + $1.count }
        if conflicts > 0 || !report.unreadable.isEmpty || !report.waitingForDownload.isEmpty {
            Section {
                if conflicts > 0 {
                    LabeledContent(String(localized: "Zwei Werte für ein Feld", bundle: .module)) {
                        Text(conflicts, format: .number)
                    }
                }
                if !report.waitingForDownload.isEmpty {
                    LabeledContent(String(localized: "Noch nicht geladen", bundle: .module)) {
                        Text(report.waitingForDownload.count, format: .number)
                    }
                }
                if !report.unreadable.isEmpty {
                    DisclosureGroup(String(localized: "Unlesbare Dateien", bundle: .module)) {
                        ForEach(report.unreadable, id: \.path) { file in
                            Text(verbatim: file.path)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    .accessibilityIdentifier("sync.unreadable")
                }
            } header: {
                Text("Letzter Abgleich", bundle: .module)
            } footer: {
                Text("Unlesbare und noch nicht geladene Dateien bleiben unverändert liegen; Quill versucht es bei jedem Abgleich wieder.", bundle: .module)
            }
        }
    }
}

/// Status in einer Zeile, auch für die Sidebar.
struct SyncStatusText: View {
    let sync: SyncController

    var body: some View {
        switch sync.status {
        case .off:
            Text("Aus", bundle: .module)
        case .idle:
            if let date = sync.lastSyncDate {
                Text("Abgeglichen \(date, format: .relative(presentation: .named))", bundle: .module)
            } else {
                Text("Bereit", bundle: .module)
            }
        case .syncing(let progress):
            HStack(spacing: 4) {
                Text("Gleicht ab …", bundle: .module)
                if progress.total > 0 {
                    Text(verbatim: "\(progress.done.formatted()) / \(progress.total.formatted())")
                        .monospacedDigit()
                }
            }
        case .paused:
            Text("Pausiert", bundle: .module)
        case .needsConfirmation:
            Text("Wartet auf deine Zustimmung", bundle: .module)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
        }
    }
}

#endif
