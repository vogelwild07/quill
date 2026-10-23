#if canImport(AppKit)
import AppKit
import OSLog
import QuillAI
import QuillEditor
import QuillEditorCore
import QuillModel
import SwiftUI

/// Anfrage „Seite › To-dos vorschlagen …“: die markierten Absätze und ihr Editor.
struct TodoRequest: Identifiable {
    let id = UUID()
    /// Blöcke der Markierung; leer, wenn kein Editor den Fokus oder nichts markiert hatte.
    let blocks: [EditorBlock]
    /// Editor mit der Markierung, nur wenn bearbeitbar; unter ihren letzten Block kommen die To-dos.
    weak var editor: BlockEditorController?

    /// Markierung im Editor, der in `window` den Fokus hat.
    @MainActor
    init(focusedIn window: NSWindow?) {
        let editor = BlockEditorController.focused(in: window)
        let ids = Set(editor?.selectedBlockIDs ?? [])
        blocks = editor?.document.blocks.filter { ids.contains($0.id) } ?? []
        // Seite im Papierkorb oder Lesemodus: Vorschläge ja, Einfügen nein.
        self.editor = editor?.allowsEditing == true ? editor : nil
    }
}

/// To-dos aus markierten Absätzen (16.3, ADR-032).
@MainActor
@Observable
final class TodoModel {
    enum Phase: Equatable {
        case working
        case done([String])
        case failed(String)
    }

    private(set) var phase = Phase.working
    @ObservationIgnored private let blocks: [EditorBlock]
    @ObservationIgnored private let model: any TextModel

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "ai")

    init(blocks: [EditorBlock], model: any TextModel) {
        self.blocks = blocks
        self.model = model
    }

    func run() async {
        phase = .working
        guard !blocks.isEmpty else {
            phase = .failed(String(localized: "Markiere zuerst die Absätze, in denen Aufgaben stehen.", bundle: .module))
            return
        }
        do {
            let parts = blocks.map { (kind: Optional($0.kind), text: $0.text) }
            phase = .done(try await TodoSuggester(model: model).suggest(parts))
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("To-dos gescheitert: \(String(describing: error), privacy: .public)")
            phase = .failed(Self.message(error))
        }
    }

    static func message(_ error: any Error) -> String {
        switch error {
        case TodoSuggester.Failure.empty:
            String(localized: "Die markierten Absätze enthalten keinen Text.", bundle: .module)
        case TodoSuggester.Failure.noTasks:
            String(localized: "In den markierten Absätzen stehen keine Aufgaben.", bundle: .module)
        default:
            AIProblem.message(error, fallback: String(localized: "Die Suche nach Aufgaben ist gescheitert.", bundle: .module))
        }
    }
}

/// Blatt mit den vorgeschlagenen To-dos: erst ansehen, dann unter der Markierung einfügen.
struct TodoView: View {
    let request: TodoRequest
    @State var model: TodoModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("To-dos vorschlagen", bundle: .module)
                .font(.headline)
            content
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            Text("Vorgeschlagen vom Sprachmodell auf diesem Mac. Die markierten Absätze bleiben, die To-dos kommen darunter.", bundle: .module)
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
                Text("Suche Aufgaben …", bundle: .module)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("todos.progress")
        case .done(let items):
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Label(item, systemImage: "square")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 240)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("todos.list")
        case .failed(let message):
            ProblemLabel(message: message)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("todos.problem")
        }
    }

    private var items: [String]? {
        if case .done(let items) = model.phase { items } else { nil }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button(String(localized: "Schließen", bundle: .module), action: dismiss)
                .keyboardShortcut(.cancelAction)
            if request.editor != nil {
                Button(String(localized: "Einfügen", bundle: .module)) { insert() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(items == nil)
                    .accessibilityIdentifier("todos.insert")
            }
        }
    }

    /// Unter dem letzten markierten Block, als ein Schritt für ⌘Z.
    private func insert() {
        guard let items, let editor = request.editor, let anchor = request.blocks.last?.id else { return }
        guard editor.acceptsInsertion else {
            NSSound.beep()
            return
        }
        dismiss()
        editor.focus()
        editor.insertBlocks(
            items.map { EditorBlock(kind: .todo, text: $0) }, after: anchor,
            actionName: String(localized: "To-dos einfügen", bundle: .module)
        )
    }
}
#endif
