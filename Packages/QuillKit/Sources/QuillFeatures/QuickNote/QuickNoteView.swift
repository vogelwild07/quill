#if canImport(AppKit)
import OSLog
import QuillEditor
import SwiftUI

/// Inhalt des Fensters der Schnellnotiz (15.3, ADR-033).
struct QuickNoteView: View {
    @Bindable var note: QuickNote
    let close: () -> Void
    @State private var failed = false

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "quicknote")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $note.draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .accessibilityLabel(Text("Notiz", bundle: .module))
                .accessibilityIdentifier("quicknote.text")
            if failed {
                Text("Die Notiz konnte nicht gesichert werden. Sie bleibt hier.", bundle: .module)
                    .foregroundStyle(.red)
            } else {
                Text("Die erste Zeile wird der Titel der neuen Seite.", bundle: .module)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button {
                    close()
                } label: {
                    Text("Abbrechen", bundle: .module)
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("quicknote.cancel")
                Button {
                    Task { await save() }
                } label: {
                    Text("Als Seite sichern", bundle: .module)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!note.canSave)
                .accessibilityIdentifier("quicknote.save")
            }
        }
        .padding(16)
        .frame(minWidth: 340, minHeight: 220)
        // Das ganze Fenster ist Glas, auch unter der Titelleiste (ADR-036).
        .background { Color.clear.quillGlass(in: Rectangle()).ignoresSafeArea() }
    }

    private func save() async {
        do {
            try await note.save()
            failed = false
            close()
        } catch {
            Self.logger.error("Schnellnotiz nicht gesichert: \(String(describing: error), privacy: .public)")
            failed = true
        }
    }
}
#endif
