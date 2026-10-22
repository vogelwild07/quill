#if canImport(AppKit)
import AppKit
import OSLog
import QuillAI
import QuillEditor
import QuillEditorCore
import QuillModel
import SwiftUI

/// Anfrage „Seite › Zusammenfassen …“: welche Seite, und wohin eingefügt werden kann.
struct SummaryRequest: Identifiable {
    let id = UUID()
    let pageID: UUID
    let title: String
    /// Editor der Seite mit der Einfügemarke, falls er beim Aufruf den Fokus hatte.
    weak var editor: NSTextView?
}

/// Zusammenfassung einer Seite (16.2, ADR-032).
@MainActor
@Observable
final class SummaryModel {
    enum Phase: Equatable {
        case working
        case done(String)
        case failed(String)
    }

    private(set) var phase = Phase.working
    @ObservationIgnored private let pageID: UUID
    @ObservationIgnored private let store: PageStore
    @ObservationIgnored private let model: any TextModel

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "ai")

    init(pageID: UUID, store: PageStore, model: any TextModel) {
        self.pageID = pageID
        self.store = store
        self.model = model
    }

    func run() async {
        phase = .working
        // Was im Editor noch wartet, gehört zur Seite.
        await EditorPersistenceBridge.flushAll(pageID: pageID)
        do {
            let blocks = try await store.blocks(of: pageID)
            phase = .done(try await PageSummarizer(model: model).summarize(blocks))
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("Zusammenfassen gescheitert: \(String(describing: error), privacy: .public)")
            phase = .failed(Self.message(error))
        }
    }

    static func message(_ error: any Error) -> String {
        switch error {
        case PageSummarizer.Failure.empty:
            String(localized: "Die Seite enthält keinen Text zum Zusammenfassen.", bundle: .module)
        case AIError.tooLong:
            String(localized: "Ein Abschnitt der Seite ist zu lang für das Sprachmodell.", bundle: .module)
        case AIError.refused:
            String(localized: "Das Sprachmodell hat diese Seite nicht zusammengefasst.", bundle: .module)
        case AIError.unsupportedLanguage:
            String(localized: "Das Sprachmodell unterstützt die Sprache dieser Seite nicht.", bundle: .module)
        case AIError.unavailable:
            String(localized: "Das Sprachmodell steht gerade nicht bereit.", bundle: .module)
        default:
            String(localized: "Die Zusammenfassung ist gescheitert.", bundle: .module)
        }
    }
}

/// Blatt mit der Zusammenfassung: kopieren oder an der Einfügemarke einfügen.
struct SummaryView: View {
    let request: SummaryRequest
    @State var model: SummaryModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Zusammenfassung", bundle: .module)
                    .font(.headline)
                Text(request.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            content
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            Text("Erstellt vom Sprachmodell auf diesem Mac. Prüfe sie, bevor du sie verwendest.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons
        }
        .padding(20)
        .frame(width: 460)
        .task { await model.run() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .working:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Fasse zusammen …", bundle: .module)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("summary.progress")
        case .done(let text):
            ScrollView {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
            .accessibilityIdentifier("summary.text")
        case .failed(let message):
            ProblemLabel(message: message)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("summary.problem")
        }
    }

    private var summary: String? {
        if case .done(let text) = model.phase { text } else { nil }
    }

    private var buttons: some View {
        HStack {
            Button(String(localized: "Kopieren", bundle: .module)) {
                guard let summary else { return }
                let clipboard = EditorClipboard.current
                clipboard.clearContents()
                clipboard.setString(summary, forType: .string)
            }
            .disabled(summary == nil)
            .accessibilityIdentifier("summary.copy")
            Spacer()
            Button(String(localized: "Schließen", bundle: .module), action: dismiss)
                .keyboardShortcut(.cancelAction)
            if request.editor != nil {
                Button(String(localized: "Einfügen", bundle: .module)) { insert() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(summary == nil)
                    .accessibilityIdentifier("summary.insert")
            }
        }
    }

    /// Wie getippt an der Einfügemarke: ein Absatz, ⌘Z nimmt ihn zurück.
    private func insert() {
        guard let summary, let editor = request.editor else { return }
        dismiss()
        editor.window?.makeFirstResponder(editor)
        // Eigener Schritt für ⌘Z, nicht mit dem zuletzt Getippten zusammen.
        editor.breakUndoCoalescing()
        editor.insertText(summary, replacementRange: editor.selectedRange())
    }
}
#endif
