#if canImport(AppKit)
import AppKit
import QuillModel
import SwiftUI

/// „Backup wiederherstellen …“ (ADR-019): Backups wählen, bestätigen, Quill beendet
/// sich; beim nächsten Start wird getauscht.
struct BackupRestoreView: View {
    let persistence: QuillPersistence
    let dismiss: () -> Void
    /// Das Backup ist vorgemerkt. Beenden muss der Aufrufer, wenn das Sheet zu ist:
    /// Solange es offen ist, ignoriert AppKit `terminate`.
    let requested: () -> Void

    @State private var entries: [BackupListEntry] = []
    @State private var selection: BackupListEntry.ID?
    @State private var isConfirming = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var selected: BackupListEntry? {
        entries.first { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backup wiederherstellen", bundle: .module)
                .font(.headline)
            Text("Quill wird danach beendet. Beim nächsten Start wird das gewählte Backup eingespielt; der aktuelle Stand bleibt als Backup „Vor dem Wiederherstellen“ erhalten.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(entries, selection: $selection) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.entry.date.formatted(date: .abbreviated, time: .shortened))
                        Text(BackupLabel.kind(item.entry.kind))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.size.formatted(.byteCount(style: .file)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("restore.row")
            }
            .frame(minHeight: 220)
            .overlay {
                if entries.isEmpty {
                    Text("Noch keine Backups", bundle: .module)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("restore.error")
            }

            HStack {
                Spacer()
                Button(String(localized: "Abbrechen", bundle: .module), role: .cancel, action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Wiederherstellen …", bundle: .module)) { isConfirming = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil || isWorking)
                    .accessibilityIdentifier("restore.confirm")
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { await load() }
        .alert(
            String(localized: "Backup vom \(selected?.entry.date.formatted(date: .abbreviated, time: .shortened) ?? "") wiederherstellen?", bundle: .module),
            isPresented: $isConfirming
        ) {
            Button(String(localized: "Wiederherstellen und beenden", bundle: .module), role: .destructive) { restore() }
            Button(String(localized: "Abbrechen", bundle: .module), role: .cancel) {}
        } message: {
            Text("Ungesicherte Änderungen werden vorher gespeichert.", bundle: .module)
        }
    }

    private func load() async {
        do {
            entries = try await persistence.backupEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() {
        guard let entry = selected?.entry else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await persistence.requestRestore(entry)
                requested()
            } catch {
                errorMessage = BackupLabel.message(for: error)
            }
            isWorking = false
        }
    }
}

/// Meldung im ersten Fenster nach dem Start.
struct LaunchNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Texte zu Backups für Liste und Meldungen.
enum BackupLabel {
    static func kind(_ kind: StoreBackup.Kind) -> String {
        switch kind {
        case .launch: String(localized: "Beim Start", bundle: .module)
        case .quit: String(localized: "Beim Beenden", bundle: .module)
        case .beforeMigration: String(localized: "Vor einer Aktualisierung der Datenbank", bundle: .module)
        case .beforeEmptyingTrash: String(localized: "Vor dem endgültigen Löschen", bundle: .module)
        case .beforeRestore: String(localized: "Vor dem Wiederherstellen", bundle: .module)
        case .beforeMove: String(localized: "Vor dem Umzug des Speicherorts", bundle: .module)
        case .setAside: String(localized: "Beiseitegelegt (alter Speicherort)", bundle: .module)
        case .other: String(localized: "Sonstiges", bundle: .module)
        }
    }

    /// „19. Okt. 2026, 10:15 (Beim Beenden)“ aus dem Ordnernamen.
    static func backup(named name: BackupName) -> String {
        guard let entry = StoreBackup.entry(at: URL(filePath: name.rawValue)) else {
            return name.rawValue.isEmpty ? String(localized: "unbekannt", bundle: .module) : name.rawValue
        }
        return "\(entry.date.formatted(date: .abbreviated, time: .shortened)) (\(kind(entry.kind)))"
    }

    static func message(for error: any Error) -> String {
        guard let error = error as? RestoreError else { return error.localizedDescription }
        return switch error {
        case .backupMissing:
            String(localized: "Das Backup gibt es nicht mehr.", bundle: .module)
        case .storeMissing:
            String(localized: "Im Backup fehlt die Datenbank.", bundle: .module)
        case .unsupportedSchema:
            String(localized: "Das Backup stammt von einer neueren Quill-Version und kann hier nicht eingespielt werden.", bundle: .module)
        case .damaged:
            String(localized: "Die Datenbank im Backup ist beschädigt.", bundle: .module)
        case .insufficientSpace(let needed, let available):
            String(localized: "Zu wenig freier Speicher: \(needed.formatted(.byteCount(style: .file))) nötig, \(available.formatted(.byteCount(style: .file))) frei.", bundle: .module)
        case .fileOperation:
            String(localized: "Die Dateien konnten nicht getauscht werden.", bundle: .module)
        case .requestNotRemovable:
            String(localized: "Die Vormerkung ließ sich nicht löschen. Damit das Wiederherstellen nicht bei jedem Start erneut läuft, wurde nichts getauscht.", bundle: .module)
        }
    }

    /// Nennt, wo der vorherige Stand liegt (relativ zu `Application Support/Quill`).
    private static func restoredMessage(backup: BackupName, previous: String?) -> String {
        let restored = String(localized: "Eingespielt: Backup vom \(Self.backup(named: backup)).", bundle: .module)
        guard let previous else { return restored }
        if previous.hasPrefix("Backups/") {
            return restored + " " + String(localized: "Der vorherige Stand liegt als Backup „Vor dem Wiederherstellen“ bereit (Ablage › Backup wiederherstellen …), Ordner „Application Support/Quill/\(previous)“.", bundle: .module)
        }
        return restored + " " + String(localized: "Der vorherige Stand liegt noch in „Application Support/Quill/\(previous)“; Quill legt ihn beim nächsten Start zu den Backups.", bundle: .module)
    }

    /// Eine Meldung nach dem Start für alles, was `prepareStore` getan hat.
    static func launchNotice(for preparation: StorePreparation) -> LaunchNotice? {
        var parts: [(title: String, message: String)] = []
        if let restore = preparation.restore {
            parts.append(outcome(restore))
        }
        if let setAside = preparation.setAside {
            parts.append((
                String(localized: "Alte Dateien beiseitegelegt", bundle: .module),
                String(localized: "Im alten Speicherort lagen noch Datenbankdateien, obwohl es „Store“ schon gab. Quill hat sie weder verwendet noch überschrieben, sondern nach „Application Support/Quill/\(setAside)“ gelegt. Sie erscheinen unter Ablage › Backup wiederherstellen … als „Beiseitegelegt“.", bundle: .module)
            ))
        }
        guard let first = parts.first else { return nil }
        return LaunchNotice(title: first.title, message: parts.map(\.message).joined(separator: "\n\n"))
    }

    /// Meldung nach dem Start: Titel und Text.
    static func outcome(_ outcome: RestoreOutcome) -> (title: String, message: String) {
        switch outcome {
        case .restored(let backup, let previous):
            (String(localized: "Backup wiederhergestellt", bundle: .module), restoredMessage(backup: backup, previous: previous))
        case .failed(let backup, let error):
            (String(localized: "Backup nicht wiederhergestellt", bundle: .module),
             String(localized: "Backup vom \(Self.backup(named: backup)): \(message(for: error)) Der bisherige Stand ist unverändert und liegt in „Application Support/Quill/Store“.", bundle: .module))
        case .interrupted:
            (String(localized: "Wiederherstellen unterbrochen", bundle: .module),
             String(localized: "Das letzte Wiederherstellen brach vor dem Tausch ab. Der bisherige Stand ist unverändert und liegt in „Application Support/Quill/Store“.", bundle: .module))
        }
    }
}
#endif
