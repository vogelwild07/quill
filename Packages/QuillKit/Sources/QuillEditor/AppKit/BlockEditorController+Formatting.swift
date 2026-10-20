#if canImport(AppKit)
import AppKit
import QuillEditorCore
import QuillModel
import SwiftUI

/// Aktionen des Menüs „Format“. Die Menüleiste schickt sie über die Responder-Kette
/// (`NSApp.sendAction(_:to: nil, from:)`); nur der Block-Editor reagiert darauf.
@MainActor
@objc public protocol EditorFormattingActions {
    func quillToggleBold(_ sender: Any?)
    func quillToggleItalic(_ sender: Any?)
    func quillToggleInlineCode(_ sender: Any?)
    func quillToggleStrikethrough(_ sender: Any?)
    func quillEditLink(_ sender: Any?)
    /// `sender` ist ein `BlockKindRequest`.
    func quillSetBlockKind(_ sender: Any?)
    func quillToggleChecked(_ sender: Any?)
    func quillMoveBlockUp(_ sender: Any?)
    func quillMoveBlockDown(_ sender: Any?)
    func quillDuplicateBlock(_ sender: Any?)
}

/// Absender für `quillSetBlockKind`: welche Blockart (Menü, Kontextmenü am Griff).
@objc public final class BlockKindRequest: NSObject {
    public let kind: BlockKind

    public init(_ kind: BlockKind) {
        self.kind = kind
    }
}

/// Inline-Formatierung: Marks umschalten und Links bearbeiten.
extension BlockEditorController {
    /// Mit Auswahl: Mark im Modell umschalten (ein Undo-Schritt). Ohne Auswahl:
    /// nur die Tipp-Attribute, wie in Pages und TextEdit.
    func toggleMark(_ mark: InlineMark) {
        guard !textView.hasMarkedText() else { return }
        let selection = textView.selectedRange()
        let start = position(atCharacter: selection.location)

        guard selection.length > 0 else {
            let block = document[start.block]
            guard block.kind.allowsInlineMarks else { return }
            var style = BlockStyle.inlineStyle(from: textView.typingAttributes)
            if style.marks.contains(mark) { style.marks.remove(mark) } else { style.marks.insert(mark) }
            var attributes = BlockStyle.attributes(for: block, ordinal: nil)
            attributes.merge(BlockStyle.inlineAttributes(for: style, kind: block.kind)) { $1 }
            textView.typingAttributes = attributes
            return
        }

        var newDocument = document
        let end = position(atCharacter: NSMaxRange(selection))
        guard newDocument.toggleMark(mark, from: start, to: end) else { return }
        textView.breakUndoCoalescing()
        apply(newDocument, cursor: nil, actionName: UndoAction.format)
        textView.setSelectedRange(selection)
    }

    /// Format › Blockart: alle Blöcke der Auswahl umwandeln, ein Undo-Schritt.
    func convertSelectedBlocks(to kind: BlockKind) {
        guard !textView.hasMarkedText(), !kind.isAtomic else { return }
        let selection = textView.selectedRange()
        let blocks = selectedBlockRange()
        var newDocument = document
        for index in blocks where !newDocument[index].kind.isAtomic {
            newDocument.setKind(kind, at: index)
        }
        guard newDocument != document else { return }
        textView.breakUndoCoalescing()
        apply(newDocument, cursor: nil, actionName: UndoAction.changeKind)
        textView.setSelectedRange(selection)
    }

    /// ⌘↩: Häkchen der To-dos in der Auswahl umschalten. Gemischt: alle abhaken.
    func toggleCheckedInSelection() {
        guard !textView.hasMarkedText() else { return }
        let todos = selectedBlockRange().filter { document[$0].kind == .todo }
        guard !todos.isEmpty else { return }
        let check = !todos.allSatisfy { document[$0].isChecked }
        let selection = textView.selectedRange()
        var newDocument = document
        for index in todos { newDocument.blocks[index].isChecked = check }
        textView.breakUndoCoalescing()
        apply(newDocument, cursor: nil, actionName: UndoAction.toggleChecked)
        textView.setSelectedRange(selection)
    }

    /// Blöcke, die die Auswahl berührt (ohne Auswahl der Block am Cursor).
    func selectedBlockRange() -> ClosedRange<Int> {
        let selection = textView.selectedRange()
        let first = blockIndex(atCharacter: selection.location)
        let last = selection.length > 0 ? blockIndex(atCharacter: NSMaxRange(selection) - 1) : first
        return first...max(first, last)
    }

    /// Ziel eines Links für ⌘K: die Auswahl, sonst der Link am Cursor.
    /// `range.length == 0` bedeutet: neuen Link als Text an der Einfügemarke einsetzen.
    func linkTarget() -> (range: NSRange, link: String?) {
        let selection = textView.selectedRange()
        let start = position(atCharacter: selection.location)
        let block = document[start.block]
        if selection.length > 0 {
            let end = position(atCharacter: NSMaxRange(selection))
            var link: String?
            if start.block == end.block, let found = block.content.linkRange(at: start.offset),
               found.range.contains(end.offset - 1) {
                link = found.link
            }
            return (selection, link)
        }
        let probe = max(0, start.offset - 1)
        if let found = block.content.linkRange(at: probe) ?? block.content.linkRange(at: start.offset) {
            let location = paragraphStarts[start.block] + found.range.lowerBound
            return (NSRange(location: location, length: found.range.count), found.link)
        }
        return (NSRange(location: selection.location, length: 0), nil)
    }

    /// Setzt (`link != nil`) oder entfernt einen Link auf `range`. Ohne Bereich wird
    /// das Ziel selbst als verlinkter Text eingesetzt.
    func setLink(_ link: String?, on range: NSRange) {
        let start = position(atCharacter: range.location)
        var newDocument = document
        let cursor: BlockPosition
        if range.length == 0 {
            guard let link, document[start.block].kind.allowsInlineMarks else { return }
            let inline = InlineText(link, spans: [InlineSpan(0..<link.utf16.count, marks: [], link: link)])
            cursor = newDocument.insertInline(inline, from: start, to: start)
        } else {
            let end = position(atCharacter: NSMaxRange(range))
            guard newDocument.setLink(link, from: start, to: end) else { return }
            cursor = end
        }
        textView.breakUndoCoalescing()
        apply(newDocument, cursor: cursor, actionName: UndoAction.link)
    }

    /// ⌘K: Popover unter der Auswahl zum Eingeben, Ändern oder Entfernen eines Links.
    func editLink() {
        guard !textView.hasMarkedText() else { return }
        let target = linkTarget()
        let block = document[blockIndex(atCharacter: target.range.location)]
        guard block.kind.allowsInlineMarks else {
            NSSound.beep()
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        let editor = LinkEditorView(link: target.link ?? "", canRemove: target.link != nil) { [weak self, weak popover] result in
            popover?.performClose(nil)
            guard let self else { return }
            switch result {
            case .set(let link): self.setLink(Self.normalizedLink(link), on: target.range)
            case .remove: self.setLink(nil, on: target.range)
            case .cancel: break
            }
            self.focus()
        }
        popover.contentViewController = NSHostingController(rootView: editor)
        var anchor = textView.firstRect(forCharacterRange: target.range, actualRange: nil)
        if let window = textView.window {
            anchor = textView.convert(window.convertFromScreen(anchor), from: nil)
        }
        popover.show(relativeTo: anchor, of: textView, preferredEdge: .maxY)
    }

    /// Ergänzt `https://` bei Eingaben ohne Schema (`quill.app` → `https://quill.app`).
    static func normalizedLink(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@"), !trimmed.contains(":") { return "mailto:" + trimmed }
        if let url = URL(string: trimmed), url.scheme != nil { return trimmed }
        return "https://" + trimmed
    }
}

/// Inhalt des Link-Popovers.
struct LinkEditorView: View {
    enum Result { case set(String), remove, cancel }

    @State var link: String
    let canRemove: Bool
    let finish: (Result) -> Void

    init(link: String, canRemove: Bool, finish: @escaping (Result) -> Void) {
        _link = State(initialValue: link)
        self.canRemove = canRemove
        self.finish = finish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(String(localized: "Link", bundle: .module), text: $link, prompt: Text(verbatim: "https://"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { submit() }
                .onExitCommand { finish(.cancel) }
                .accessibilityIdentifier("editor.link.field")
            HStack {
                if canRemove {
                    Button(String(localized: "Link entfernen", bundle: .module)) { finish(.remove) }
                }
                Spacer()
                Button(String(localized: "Fertig", bundle: .module)) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty && !canRemove)
            }
        }
        .padding(14)
    }

    private func submit() {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        finish(trimmed.isEmpty ? (canRemove ? .remove : .cancel) : .set(trimmed))
    }
}
#endif
