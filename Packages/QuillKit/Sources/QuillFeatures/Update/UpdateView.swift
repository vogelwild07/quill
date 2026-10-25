#if canImport(AppKit)
import QuillDesign
import QuillUpdate
import SwiftUI

/// Inhalt des Fensters „Update“ (ADR-037): ein Zustand, ein Satz, passende Knöpfe.
struct UpdateView: View {
    let model: UpdateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityIdentifier("update.title")
            if let message {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("update.message")
            }
            progress
            if case .found(let offer) = model.phase, let notes = Self.plainNotes(offer.notes) {
                ScrollView {
                    Text(verbatim: notes)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 160)
                .background(.background.secondary, in: .rect(cornerRadius: QuillDesign.Radius.large))
                .accessibilityLabel(Text("Neu in dieser Version", bundle: .module))
                .accessibilityIdentifier("update.notes")
            }
            buttons
        }
        .padding(20)
        .frame(width: 440)
    }

    private var title: String {
        switch model.phase {
        case .idle, .checking: String(localized: "Suche nach Updates …", bundle: .module)
        case .upToDate: String(localized: "Quill ist aktuell.", bundle: .module)
        case .found(let offer): String(localized: "Quill \(offer.version) ist da.", bundle: .module)
        case .backingUp: String(localized: "Backup wird angelegt …", bundle: .module)
        case .downloading: String(localized: "Update wird geladen …", bundle: .module)
        case .preparing: String(localized: "Update wird geprüft …", bundle: .module)
        case .installing: String(localized: "Quill wird neu gestartet …", bundle: .module)
        case .failed: String(localized: "Update nicht möglich", bundle: .module)
        }
    }

    private var message: String? {
        switch model.phase {
        case .idle, .checking, .downloading, .preparing, .installing: nil
        case .upToDate: String(localized: "Du hast die neueste Version (\(Self.currentVersion)).", bundle: .module)
        case .found: String(localized: "Du hast Version \(Self.currentVersion). Vor der Installation legt Quill ein Backup deiner Notizen an.", bundle: .module)
        case .backingUp: String(localized: "Danach lädt Quill das Update und prüft die Signatur.", bundle: .module)
        case .failed(let failure): Self.message(for: failure)
        }
    }

    static func message(for failure: UpdateModel.Failure) -> String {
        switch failure {
        case .notInApplications:
            String(localized: "Quill kann sich nur selbst aktualisieren, wenn es im Ordner „Programme“ liegt. Zieh Quill aus der .dmg nach „Programme“ und starte es dort.", bundle: .module)
        case .badSignature:
            String(localized: "Die Signatur oder Prüfsumme des Updates stimmt nicht. Quill hat nichts installiert.", bundle: .module)
        case .damaged:
            String(localized: "Das Update ist beschädigt. Quill hat nichts installiert.", bundle: .module)
        case .network:
            String(localized: "GitHub ist gerade nicht erreichbar. Prüf die Verbindung und versuch es später noch einmal.", bundle: .module)
        case .notAllowed:
            String(localized: "Das Update kommt nicht über HTTPS von github.com/vogelwild07/quill. Quill hat nichts installiert.", bundle: .module)
        case .backupFailed:
            String(localized: "Das Backup vor der Installation ist gescheitert. Quill hat nichts installiert.", bundle: .module)
        case .couldNotQuit:
            String(localized: "Quill ließ sich nicht beenden. Schließ offene Fragen und versuch es noch einmal.", bundle: .module)
        case .other(let description):
            String(localized: "Das Update ist gescheitert: \(description)", bundle: .module)
        }
    }

    @ViewBuilder private var progress: some View {
        switch model.phase {
        case .checking, .backingUp, .preparing, .installing:
            ProgressView().progressViewStyle(.linear)
        case .downloading(let fraction?):
            ProgressView(value: fraction).progressViewStyle(.linear)
        case .downloading(nil):
            ProgressView().progressViewStyle(.linear)
        case .idle, .upToDate, .found, .failed:
            EmptyView()
        }
    }

    @ViewBuilder private var buttons: some View {
        HStack {
            switch model.phase {
            case .found:
                Button(String(localized: "Diese Version überspringen", bundle: .module)) { model.choose(.skip) }
                    .accessibilityIdentifier("update.skip")
                Spacer()
                Button(String(localized: "Später", bundle: .module)) { model.choose(.later) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("update.later")
                Button(String(localized: "Installieren", bundle: .module)) { model.choose(.install) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("update.install")
            case .failed where model.canRetry:
                Spacer()
                Button(String(localized: "Abbrechen", bundle: .module)) { model.close() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Noch einmal", bundle: .module)) { model.retry() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("update.retry")
            case .upToDate, .failed:
                Spacer()
                Button(String(localized: "OK", bundle: .module)) { model.close() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("update.ok")
            case .idle, .checking, .backingUp, .downloading, .preparing, .installing:
                Spacer()
                if model.canCancel {
                    Button(String(localized: "Abbrechen", bundle: .module)) { model.cancel() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("update.cancel")
                }
            }
        }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Text der Versionsliste ohne Tags; Quill zeigt keine Webinhalte an.
    static func plainNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let plain = notes.replacing(#/<[^>]*>/#, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty ? nil : plain
    }
}
#endif
