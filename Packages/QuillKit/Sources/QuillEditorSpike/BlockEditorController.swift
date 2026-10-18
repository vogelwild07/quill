#if os(macOS)
import AppKit
import QuillEditor

/// Verbindet `EditorDocument` mit einem TextKit-2-`NSTextView`.
///
/// - Normales Tippen (inkl. IME, Autokorrektur) erledigt die Text-View selbst; danach
///   wird das Modell aus dem Textspeicher gelesen.
/// - Änderungen über Blockgrenzen (Enter, Backspace am Anfang, mehrzeiliges Einfügen,
///   Auswahl über mehrere Blöcke) laufen über `EditorDocument` und werden als Diff
///   in den Speicher geschrieben – über `shouldChangeText`/`didChangeText`, damit
///   Undo/Redo der Text-View alles erfasst.
@MainActor
public final class BlockEditorController: NSObject, NSTextViewDelegate, @MainActor NSTextStorageDelegate {
    public let scrollView: NSScrollView
    let textView: BlockTextView
    public private(set) var document: EditorDocument
    /// Wird nach jeder Änderung des Dokuments aufgerufen.
    public var onChange: ((EditorDocument) -> Void)?

    private var renderer = BlockRenderer()
    private let layoutDelegate = BlockLayoutDelegate()
    private var paragraphStarts: [Int] = []
    private var isApplying = false
    private var lastInsertedString: String?
    private var editedRange: NSRange?
    private var editedDelta = 0
    private lazy var slashMenu = SlashMenuController(editor: self)

    public init(document: EditorDocument) {
        self.document = document

        let layoutManager = NSTextLayoutManager()
        let contentStorage = NSTextContentStorage()
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.textContainer = container

        textView = BlockTextView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
        scrollView = NSScrollView()
        super.init()

        layoutManager.delegate = layoutDelegate
        configureTextView()
        loadStorage()
        observeUndo()
    }

    /// Undo/Redo der Text-View löst kein `textDidChange` aus; danach das Modell neu lesen.
    private func observeUndo() {
        for name in [NSNotification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let sender = (note.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, let manager = self.textView.undoManager, sender == ObjectIdentifier(manager) else { return }
                    self.slashMenu.close()
                    self.syncFromStorage()
                }
            }
        }
    }

    private func configureTextView() {
        textView.editor = self
        textView.delegate = self
        textView.textStorage?.delegate = self
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = CGSize(width: 0, height: 0)
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
    }

    private func loadStorage() {
        let ordinals = BlockRenderer.ordinals(for: document)
        let text = renderer.render(document.blocks[...], ordinals: ordinals)
        isApplying = true
        textView.textStorage?.setAttributedString(text)
        isApplying = false
        rebuildParagraphStarts()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.typingAttributes = BlockStyle.attributes(for: document[0], ordinal: nil)
    }

    /// Ersetzt das gesamte Dokument (z. B. Laden einer anderen Seite). Leert Undo.
    public func load(_ newDocument: EditorDocument) {
        document = newDocument
        loadStorage()
        textView.undoManager?.removeAllActions()
    }

    // MARK: Positionen

    private func rebuildParagraphStarts() {
        paragraphStarts.removeAll(keepingCapacity: true)
        var location = 0
        for block in document.blocks {
            paragraphStarts.append(location)
            location += BlockRenderer.displayLength(of: block) + 1
        }
        paragraphStarts.append(location)
    }

    func blockIndex(atCharacter location: Int) -> Int {
        var low = 0
        var high = document.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if paragraphStarts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }

    func position(atCharacter location: Int) -> BlockPosition {
        let block = blockIndex(atCharacter: location)
        let length = BlockRenderer.displayLength(of: document[block])
        return BlockPosition(block: block, offset: min(location - paragraphStarts[block], length))
    }

    func characterLocation(of position: BlockPosition) -> Int {
        let block = min(position.block, document.count - 1)
        return paragraphStarts[block] + min(position.offset, BlockRenderer.displayLength(of: document[block]))
    }

    private func paragraphRange(ofBlock index: Int) -> NSRange {
        NSRange(location: paragraphStarts[index], length: paragraphStarts[index + 1] - paragraphStarts[index])
    }

    // MARK: Struktur anwenden

    /// Schreibt `newDocument` als minimalen Diff in den Textspeicher (undo-fähig).
    func apply(_ newDocument: EditorDocument, cursor: BlockPosition?, actionName: String? = nil) {
        let old = document.blocks
        let new = newDocument.blocks
        var prefix = 0
        while prefix < min(old.count, new.count) && old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix
            && old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }

        let oldRange = NSRange(
            location: paragraphStarts[prefix],
            length: paragraphStarts[old.count - suffix] - paragraphStarts[prefix]
        )
        let ordinals = BlockRenderer.ordinals(for: newDocument)
        let replacement = renderer.render(new[prefix..<(new.count - suffix)], ordinals: ordinals)

        if oldRange.length > 0 || replacement.length > 0 {
            isApplying = true
            if textView.shouldChangeText(in: oldRange, replacementString: replacement.string) {
                textView.textStorage?.replaceCharacters(in: oldRange, with: replacement)
                textView.didChangeText()
            }
            isApplying = false
        }
        if let actionName { textView.undoManager?.setActionName(actionName) }

        document = newDocument
        rebuildParagraphStarts()
        refreshOrdinals()
        if let cursor {
            let location = characterLocation(of: cursor)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.typingAttributes = BlockStyle.attributes(for: document[cursor.block], ordinal: nil)
        }
        onChange?(document)
    }

    /// Nummern nummerierter Punkte nachführen (nicht undo-relevant, abgeleitet).
    private func refreshOrdinals() {
        guard let storage = textView.textStorage else { return }
        let ordinals = BlockRenderer.ordinals(for: document)
        var changes: [(NSRange, Int)] = []
        for (index, block) in document.blocks.enumerated() where block.kind == .numbered {
            let range = paragraphRange(ofBlock: index)
            let current = storage.attribute(.quillOrdinal, at: NSMaxRange(range) - 1, effectiveRange: nil) as? Int
            if let ordinal = ordinals[block.id], ordinal != current { changes.append((range, ordinal)) }
        }
        guard !changes.isEmpty else { return }
        isApplying = true
        storage.beginEditing()
        for (range, ordinal) in changes { storage.addAttribute(.quillOrdinal, value: ordinal, range: range) }
        storage.endEditing()
        isApplying = false
    }

    // MARK: NSTextStorageDelegate

    public func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range: NSRange,
        changeInLength delta: Int
    ) {
        guard !isApplying, editedMask.contains(.editedCharacters) else { return }
        editedRange = editedRange.map { NSUnionRange($0, range) } ?? range
        editedDelta += delta
    }

    // MARK: NSTextViewDelegate – Abfangen

    public func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        guard !isApplying, let replacement = replacementString else { return true }
        if textView.hasMarkedText() { return true }
        // Undo/Redo spielt frühere Änderungen 1:1 zurück; danach wird das Modell gelesen.
        if let undoManager = textView.undoManager, undoManager.isUndoing || undoManager.isRedoing { return true }
        lastInsertedString = replacement

        let string = textView.string as NSString
        let crossesBlocks = range.length > 0
            && string.rangeOfCharacter(from: CharacterSet(charactersIn: "\n"), options: [], range: range).location != NSNotFound
        let insertsBlocks = replacement.contains("\n") || replacement.contains("\r")
        let start = position(atCharacter: range.location)
        let touchesAtomic = document[start.block].kind.isAtomic

        guard crossesBlocks || insertsBlocks || touchesAtomic else { return true }

        var newDocument = document
        let text = replacement.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if touchesAtomic && range.length == 0 {
            guard !text.isEmpty else { return false }
            // Tippen vor/hinter Trenner oder Bild: neuer Absatz davor bzw. dahinter.
            let index = start.offset == 0 ? start.block : start.block + 1
            newDocument.insertBlock(EditorBlock(), at: index)
            let cursor = newDocument.insertText(text, at: BlockPosition(block: index, offset: 0))
            apply(newDocument, cursor: cursor, actionName: "Tippen")
            return false
        }
        guard NSMaxRange(range) < string.length else { return false }
        let end = position(atCharacter: NSMaxRange(range))
        let cursor = newDocument.replace(from: start, to: end, with: text)
        apply(newDocument, cursor: cursor, actionName: "Tippen")
        return false
    }

    public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if slashMenu.isVisible, slashMenu.handle(selector) { return true }
        let selection = textView.selectedRange()
        let caret = position(atCharacter: selection.location)

        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if document[caret.block].kind == .code && selection.length == 0 {
                textView.insertLineBreak(nil)
                return true
            }
            var newDocument = document
            var cursor = caret
            if selection.length > 0 {
                cursor = newDocument.replace(from: caret, to: position(atCharacter: NSMaxRange(selection)), with: "")
            }
            cursor = newDocument.splitBlock(at: cursor)
            apply(newDocument, cursor: cursor, actionName: "Neuer Block")
            return true

        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            if document[caret.block].kind == .code && selector == #selector(NSResponder.insertTab(_:)) {
                return false
            }
            let indent = selector == #selector(NSResponder.insertTab(_:))
            let last = blockIndex(atCharacter: max(selection.location, NSMaxRange(selection) - (selection.length > 0 ? 1 : 0)))
            var newDocument = document
            var changed = false
            for index in caret.block...last {
                changed = (indent ? newDocument.indent(at: index) : newDocument.outdent(at: index)) || changed
            }
            if changed {
                apply(newDocument, cursor: nil, actionName: indent ? "Einrücken" : "Ausrücken")
                textView.setSelectedRange(remap(selection, from: caret.block, to: last))
            }
            return true

        case #selector(NSResponder.deleteBackward(_:)):
            guard selection.length == 0 else { return false }
            if caret.offset == 0 {
                var newDocument = document
                if let cursor = newDocument.deleteBackwardAtStart(of: caret.block) {
                    apply(newDocument, cursor: cursor, actionName: "Löschen")
                } else {
                    NSSound.beep()
                }
                return true
            }
            if document[caret.block].kind.isAtomic {
                var newDocument = document
                let cursor = newDocument.deleteBlock(at: caret.block)
                apply(newDocument, cursor: cursor, actionName: "Löschen")
                return true
            }
            return false

        default:
            return false
        }
    }

    /// Hält die Auswahl über dieselben Blöcke, nachdem sich Einrückungen geändert haben.
    private func remap(_ selection: NSRange, from first: Int, to last: Int) -> NSRange {
        let start = paragraphStarts[first]
        let end = paragraphStarts[last + 1] - 1
        return selection.length == 0
            ? NSRange(location: min(selection.location, end), length: 0)
            : NSRange(location: start, length: end - start)
    }

    // MARK: NSTextViewDelegate – nach dem Tippen

    public func textDidChange(_ notification: Notification) {
        guard !isApplying else { return }
        if !syncSingleParagraph() { syncFromStorage() }

        let inserted = lastInsertedString
        lastInsertedString = nil
        guard !textView.hasMarkedText() else { return }
        let caret = position(atCharacter: textView.selectedRange().location)

        if inserted == " " || inserted == "-" {
            var newDocument = document
            if let cursor = newDocument.applyMarkdownShortcut(at: caret) {
                // Eigener Undo-Schritt: ⌘Z stellt das getippte Kürzel wieder her.
                textView.breakUndoCoalescing()
                apply(newDocument, cursor: cursor, actionName: "Markdown-Kürzel")
                return
            }
        }
        if inserted == "/" {
            slashMenu.openIfAllowed(slashLocation: textView.selectedRange().location - 1)
        } else if slashMenu.isVisible {
            slashMenu.update()
        }
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        if slashMenu.isVisible { slashMenu.update() }
    }

    /// Schneller Pfad für normales Tippen: Die Änderung liegt in genau einem Absatz und
    /// hat keine Blockgrenze erzeugt oder entfernt. Dann nur diesen Block nachführen.
    private func syncSingleParagraph() -> Bool {
        guard let storage = textView.textStorage, let editedRange else { return false }
        let string = storage.string as NSString
        guard paragraphStarts[document.count] + editedDelta == string.length else { return false }

        let index = blockIndex(atCharacter: editedRange.location)
        let start = paragraphStarts[index]
        let newEnd = paragraphStarts[index + 1] + editedDelta - 1
        guard newEnd >= start, newEnd < string.length, NSMaxRange(editedRange) <= newEnd,
              string.character(at: newEnd) == StorageCharacter.paragraphEnd,
              !document[index].kind.isAtomic else { return false }
        let body = NSRange(location: start, length: newEnd - start)
        guard string.rangeOfCharacter(from: CharacterSet(charactersIn: "\n"), options: [], range: body).location == NSNotFound
        else { return false }

        let expectedID = document[index].id.uuidString
        if editedRange.length > 0,
           storage.attribute(.quillBlockID, at: editedRange.location, effectiveRange: nil) as? String != expectedID {
            return false
        }
        document[index].text = string.substring(with: body).replacingOccurrences(of: StorageCharacter.softBreak, with: "\n")
        for later in (index + 1)...document.count { paragraphStarts[later] += editedDelta }
        self.editedRange = nil
        editedDelta = 0
        onChange?(document)
        return true
    }

    /// Modell aus dem Textspeicher lesen, Attribute der bearbeiteten Absätze vereinheitlichen.
    private func syncFromStorage() {
        guard let storage = textView.textStorage else { return }
        let (blocks, repaired) = BlockRenderer.parse(storage)
        document = EditorDocument(blocks: blocks)
        rebuildParagraphStarts()

        var normalize = repaired
        if let editedRange {
            let string = storage.string as NSString
            let clamped = NSIntersectionRange(editedRange, NSRange(location: 0, length: string.length))
            normalize.append(string.paragraphRange(for: clamped))
        }
        editedRange = nil
        editedDelta = 0

        let ordinals = BlockRenderer.ordinals(for: document)
        isApplying = true
        storage.beginEditing()
        for range in normalize where range.length > 0 {
            let first = blockIndex(atCharacter: range.location)
            let last = blockIndex(atCharacter: NSMaxRange(range) - 1)
            for index in first...last {
                let block = document[index]
                storage.addAttributes(BlockStyle.attributes(for: block, ordinal: ordinals[block.id]), range: paragraphRange(ofBlock: index))
            }
        }
        storage.endEditing()
        isApplying = false
        refreshOrdinals()
        onChange?(document)
    }

    // MARK: Aktionen

    func toggleChecked(atCharacter location: Int) {
        let index = blockIndex(atCharacter: location)
        var newDocument = document
        newDocument.toggleChecked(at: index)
        let selection = textView.selectedRange()
        apply(newDocument, cursor: nil, actionName: "Abhaken")
        textView.setSelectedRange(selection)
    }

    /// Ändert die Art des Blocks am Cursor (Slash-Menü).
    func setKind(_ kind: BlockKind, ofBlockAtCharacter location: Int) {
        let index = blockIndex(atCharacter: location)
        var newDocument = document
        newDocument.setKind(kind, at: index)
        var cursor = BlockPosition(block: index, offset: newDocument[index].length)
        if kind.isAtomic { cursor = BlockPosition(block: index + 1, offset: 0) }
        if kind == .image, let image = Self.chooseImage() {
            renderer.images[newDocument[index].id] = image
        } else if kind == .image {
            return
        }
        apply(newDocument, cursor: cursor, actionName: "Blockart ändern")
    }

    /// Bild für den Spike über einen Öffnen-Dialog wählen.
    private static func chooseImage() -> NSImage? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Fügt ein Bild als neuen Block hinter dem Cursor-Block ein (Tests, Drop).
    func insertImage(_ image: NSImage, afterCharacter location: Int) {
        let index = blockIndex(atCharacter: location)
        var newDocument = document
        let block = EditorBlock(kind: .image)
        renderer.images[block.id] = image
        let cursor = newDocument.insertBlocks([block, EditorBlock()], at: BlockPosition(block: index, offset: BlockRenderer.displayLength(of: document[index])))
        apply(newDocument, cursor: cursor, actionName: "Bild einfügen")
    }

    // MARK: Ziehen

    /// Zu ziehende Blöcke: die ausgewählten, wenn der Griff zur Auswahl gehört, sonst der eine Block.
    func dragBlocks(forHandleAtCharacter location: Int) -> (ids: [UUID], markdown: String, viewFrame: CGRect) {
        let handleBlock = blockIndex(atCharacter: location)
        let selection = textView.selectedRange()
        var range = handleBlock...handleBlock
        if selection.length > 0 {
            let first = blockIndex(atCharacter: selection.location)
            let last = blockIndex(atCharacter: NSMaxRange(selection) - 1)
            if (first...last).contains(handleBlock) { range = first...last }
        }
        let ids = range.map { document[$0].id }
        let markdown = MarkdownSerializer.markdown(for: document, blocks: range.lowerBound..<(range.upperBound + 1))

        var frame = CGRect.null
        if let manager = textView.textLayoutManager, let content = manager.textContentManager {
            let start = paragraphStarts[range.lowerBound]
            let end = paragraphStarts[range.upperBound + 1]
            if let from = content.location(content.documentRange.location, offsetBy: start),
               let to = content.location(content.documentRange.location, offsetBy: end - 1),
               let textRange = NSTextRange(location: from, end: to) {
                manager.enumerateTextLayoutFragments(from: textRange.location, options: [.ensuresLayout]) { fragment in
                    frame = frame.union(self.textView.viewFrame(of: fragment))
                    return fragment.rangeInElement.endLocation.compare(textRange.endLocation) == .orderedAscending
                }
            }
        }
        if frame.isNull { frame = CGRect(x: 0, y: 0, width: 200, height: 24) }
        return (ids, markdown, frame)
    }

    /// Verschiebt Blöcke vor den Block mit Index `destination` (vor dem Verschieben).
    @discardableResult
    func moveBlocks(withIDs ids: [UUID], to destination: Int) -> Bool {
        let wanted = Set(ids)
        let indices = IndexSet(document.blocks.indices.filter { wanted.contains(document[$0].id) })
        guard !indices.isEmpty else { return false }
        if let first = indices.first, let last = indices.last, last - first + 1 == indices.count,
           (first...(last + 1)).contains(destination) {
            return false
        }
        var newDocument = document
        let range = newDocument.moveBlocks(indices, to: destination)
        apply(newDocument, cursor: nil, actionName: "Blöcke verschieben")
        let start = paragraphStarts[range.lowerBound]
        let end = paragraphStarts[range.upperBound] - 1
        textView.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
        return true
    }

    // MARK: Zwischenablage

    /// Blöcke der Auswahl; Rand-Blöcke auf den ausgewählten Text gekürzt.
    private func selectedBlocks() -> [EditorBlock]? {
        let selection = textView.selectedRange()
        guard selection.length > 0 else { return nil }
        let start = position(atCharacter: selection.location)
        var end = position(atCharacter: NSMaxRange(selection))
        guard start.block != end.block else { return nil }
        if end.offset == 0 && NSMaxRange(selection) == paragraphStarts[end.block] {
            end = BlockPosition(block: end.block - 1, offset: BlockRenderer.displayLength(of: document[end.block - 1]))
        }
        var blocks = Array(document.blocks[start.block...end.block])
        if !blocks[0].kind.isAtomic {
            blocks[0].text = EditorDocument.split(blocks[0].text, at: start.offset).1
        }
        let lastIndex = blocks.count - 1
        if !blocks[lastIndex].kind.isAtomic {
            let trimmedEnd = lastIndex == 0 ? end.offset - start.offset : end.offset
            blocks[lastIndex].text = EditorDocument.split(blocks[lastIndex].text, at: trimmedEnd).0
        }
        return blocks
    }

    /// Schreibt Klartext, Markdown, RTF und Quill-Blöcke. `false` = einfache Auswahl
    /// innerhalb eines Blocks; dann übernimmt die Text-View.
    func copySelection(to pasteboard: NSPasteboard) -> Bool {
        guard let blocks = selectedBlocks() else { return false }
        let slice = EditorDocument(blocks: blocks)
        let markdown = MarkdownSerializer.markdown(for: slice, blocks: 0..<slice.count)
        let plain = MarkdownSerializer.plainText(for: blocks)

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(plain, forType: .string)
        item.setString(markdown, forType: .markdown)
        if let data = try? JSONEncoder().encode(blocks) { item.setData(data, forType: .quillBlocks) }
        if let storage = textView.textStorage {
            let rich = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: textView.selectedRange()))
            rich.mutableString.replaceOccurrences(of: StorageCharacter.softBreak, with: "\n", options: [], range: NSRange(location: 0, length: rich.length))
            if let rtf = rich.rtf(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]) {
                item.setData(rtf, forType: .rtf)
            }
        }
        pasteboard.writeObjects([item])
        return true
    }

    func cutSelection(to pasteboard: NSPasteboard) -> Bool {
        guard copySelection(to: pasteboard) else { return false }
        let selection = textView.selectedRange()
        var newDocument = document
        let cursor = newDocument.replace(from: position(atCharacter: selection.location), to: position(atCharacter: NSMaxRange(selection)), with: "")
        apply(newDocument, cursor: cursor, actionName: "Ausschneiden")
        return true
    }

    /// Fügt Quill-Blöcke verlustfrei ein, sonst Klartext (keine fremden Formate).
    func paste(from pasteboard: NSPasteboard) -> Bool {
        let selection = textView.selectedRange()
        if let data = pasteboard.data(forType: .quillBlocks),
           let blocks = try? JSONDecoder().decode([EditorBlock].self, from: data) {
            var newDocument = document
            var caret = position(atCharacter: selection.location)
            if selection.length > 0 {
                caret = newDocument.replace(from: caret, to: position(atCharacter: NSMaxRange(selection)), with: "")
            }
            let fresh = blocks.map { block -> EditorBlock in
                var copy = block
                copy.id = UUID()
                return copy
            }
            let cursor = newDocument.insertBlocks(fresh, at: caret)
            apply(newDocument, cursor: cursor, actionName: "Einsetzen")
            return true
        }
        if let string = pasteboard.string(forType: .string) {
            textView.insertText(string, replacementRange: selection)
            return true
        }
        return false
    }

    // MARK: Slash-Menü-Hilfen

    var caretLocation: Int { textView.selectedRange().location }

    func text(in range: NSRange) -> String {
        (textView.string as NSString).substring(with: range)
    }

    func screenRect(forCharacter location: Int) -> CGRect {
        textView.firstRect(forCharacterRange: NSRange(location: location, length: 1), actualRange: nil)
    }

    func deleteText(in range: NSRange) {
        textView.insertText("", replacementRange: range)
    }

    var window: NSWindow? { textView.window }
}
#endif
