#if canImport(AppKit)
import AppKit
import QuillEditor
import QuillEditorCore
import SwiftUI

/// Anfrage „Format › Sprachnotiz …“: Editor und Block an der Einfügemarke.
struct VoiceNoteRequest: Identifiable {
    let id = UUID()
    weak var editor: BlockEditorController?
    /// Unter diesen Block kommt der Text.
    let anchor: UUID

    /// `nil` ohne Einfügemarke in einem bearbeitbaren Editor.
    @MainActor
    init?(focusedIn window: NSWindow?) {
        guard let editor = BlockEditorController.focused(in: window), editor.allowsEditing,
              let anchor = editor.cursorBlockID else { return nil }
        self.editor = editor
        self.anchor = anchor
    }
}

/// Blatt „Sprachnotiz“ (17.2, ADR-034): aufnehmen, Abschrift live ansehen, dann einfügen.
struct VoiceNoteView: View {
    let request: VoiceNoteRequest
    @State var model: VoiceNoteModel
    let dismiss: () -> Void
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sprachnotiz", bundle: .module)
                .font(.headline)
            transcript
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 240, alignment: .topLeading)
            if let message = problem ?? failure {
                ProblemLabel(message: message)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("voice.problem")
            }
            Text("Erkannt auf diesem Mac. Die Aufnahme wird nicht gespeichert, nur der Text kommt unter die Einfügemarke.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons
        }
        .padding(20)
        .frame(width: 460)
        .onDisappear { model.cancel() }
    }

    private var failure: String? {
        if case .failed(let message) = model.phase { message } else { nil }
    }

    private var transcript: some View {
        ScrollView {
            Group {
                if model.text.isEmpty, model.isRecording {
                    Text("Sprich jetzt …", bundle: .module)
                        .foregroundStyle(.secondary)
                } else if model.text.isEmpty {
                    Text("Noch kein Text.", bundle: .module)
                        .foregroundStyle(.secondary)
                } else {
                    Text(styledText)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("voice.transcript")
        }
    }

    /// Unsichere Wörter heller, bis die Erkennung sie festlegt.
    private var styledText: AttributedString {
        var pending = AttributedString(model.pending)
        pending.foregroundColor = .secondary
        let separator = model.finished.isEmpty || model.pending.isEmpty ? "" : " "
        return AttributedString(model.finished + separator) + pending
    }

    private var buttons: some View {
        HStack {
            if model.isRecording {
                Button {
                    model.stop()
                } label: {
                    Label(String(localized: "Stopp", bundle: .module), systemImage: "stop.fill")
                }
                .disabled(model.phase != .recording)
                .accessibilityIdentifier("voice.stop")
            } else {
                Button {
                    problem = nil
                    model.record()
                } label: {
                    Label(String(localized: "Aufnehmen", bundle: .module), systemImage: "mic.fill")
                }
                .accessibilityIdentifier("voice.record")
            }
            Spacer()
            Button(String(localized: "Abbrechen", bundle: .module), action: dismiss)
                .keyboardShortcut(.cancelAction)
            Button(String(localized: "Einfügen", bundle: .module)) { insert() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isRecording || model.text.isEmpty)
                .accessibilityIdentifier("voice.insert")
        }
    }

    /// Ein Absatz unter dem Block an der Einfügemarke, als ein Schritt für ⌘Z.
    private func insert() {
        // Während der Aufnahme kann der Block oder die Seite weg sein.
        guard let editor = request.editor, editor.acceptsInsertion,
              editor.document.blocks.contains(where: { $0.id == request.anchor }) else {
            problem = String(localized: "Die Stelle zum Einfügen gibt es nicht mehr. Kopiere den Text oder schließe das Blatt.", bundle: .module)
            return
        }
        let text = model.text
        dismiss()
        editor.focus()
        editor.insertBlocks(
            [EditorBlock(kind: .paragraph, text: text)], after: request.anchor,
            actionName: String(localized: "Sprachnotiz einfügen", bundle: .module)
        )
    }
}
#endif
