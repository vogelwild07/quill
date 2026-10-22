#if canImport(AppKit)
import AppKit
import OSLog
import QuillAI
import QuillEditorCore
import QuillModel
import SwiftUI

/// „Frag deine Notizen“ (16.4, ADR-032): Frage, Antwort und die Seiten, aus denen sie stammt.
@MainActor
@Observable
final class AskModel {
    enum Phase: Equatable {
        case idle
        case working
        case done(NoteAnswerer.Answer)
        case failed(String)
    }

    var question = ""
    private(set) var phase = Phase.idle
    @ObservationIgnored private let store: PageStore
    @ObservationIgnored private let model: any TextModel

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "ai")

    init(store: PageStore, model: any TextModel) {
        self.store = store
        self.model = model
    }

    var canAsk: Bool {
        phase != .working && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func ask() async {
        guard canAsk else { return }
        phase = .working
        // Was in Editoren noch wartet, soll die Suche schon finden.
        await EditorPersistenceBridge.flushAll()
        do {
            phase = .done(try await NoteAnswerer(model: model, store: store).answer(question))
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("Frage gescheitert: \(String(describing: error), privacy: .public)")
            phase = .failed(Self.message(error))
        }
    }

    static func message(_ error: any Error) -> String {
        switch error {
        case NoteAnswerer.Failure.emptyQuestion:
            String(localized: "Stell zuerst eine Frage.", bundle: .module)
        case NoteAnswerer.Failure.noSources:
            String(localized: "Zu deiner Frage habe ich keine passenden Seiten gefunden.", bundle: .module)
        default:
            AIProblem.message(error, fallback: String(localized: "Die Antwort ist gescheitert.", bundle: .module))
        }
    }
}

/// Blatt „Frag deine Notizen“: Frage stellen, Antwort lesen, Quelle öffnen.
struct AskView: View {
    @State var model: AskModel
    /// Öffnet die Seite einer Quelle und schließt das Blatt.
    let open: (UUID) -> Void
    let dismiss: () -> Void
    @FocusState private var isQuestionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Frag deine Notizen", bundle: .module)
                .font(.headline)
            HStack {
                TextField(
                    String(localized: "Frage", bundle: .module), text: $model.question,
                    prompt: Text("Was möchtest du wissen?", bundle: .module)
                )
                .labelsHidden()
                .focused($isQuestionFocused)
                .onSubmit { Task { await model.ask() } }
                .accessibilityIdentifier("ask.question")
                Button(String(localized: "Fragen", bundle: .module)) { Task { await model.ask() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canAsk)
                    .accessibilityIdentifier("ask.submit")
            }
            content
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            Text("Beantwortet vom Sprachmodell auf diesem Mac, nur aus den genannten Seiten. Prüfe die Antwort dort.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(String(localized: "Schließen", bundle: .module), action: dismiss)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { isQuestionFocused = true }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .working:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Suche in deinen Notizen …", bundle: .module)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ask.progress")
        case .done(let answer):
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(answer.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("ask.answer")
                    Text("Quellen", bundle: .module)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    ForEach(answer.sources) { source in
                        Button {
                            open(source.pageID)
                        } label: {
                            Label(Self.title(source), systemImage: "doc.text")
                        }
                        .buttonStyle(.link)
                        .accessibilityIdentifier("ask.source")
                    }
                }
            }
            .frame(maxHeight: 280)
        case .failed(let message):
            ProblemLabel(message: message)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ask.problem")
        }
    }

    static func title(_ source: NoteAnswerer.Source) -> String {
        source.title.isEmpty ? String(localized: "Ohne Titel", bundle: .module) : source.title
    }
}
#endif
