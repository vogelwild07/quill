#if canImport(AppKit)
import AppKit
import QuillModel

/// Verbindet `EditorDocument` mit einem TextKit-2-`NSTextView` (ADR-007).
///
/// - Normales Tippen (inkl. IME, Autokorrektur) erledigt die Text-View selbst; danach
///   wird das Modell aus dem Textspeicher gelesen (`+Sync`).
/// - Änderungen über Blockgrenzen (Enter, Backspace am Anfang, mehrzeiliges Einfügen,
///   Auswahl über mehrere Blöcke) laufen über `EditorDocument` (`+Input`) und werden
///   per `apply` als Diff in den Speicher geschrieben – über `shouldChangeText`/
///   `didChangeText`, damit Undo/Redo der Text-View alles erfasst.
/// - Zwischenablage und Ziehen von Blöcken: `+Clipboard`, `+Drag`.
@MainActor
public final class BlockEditorController: NSObject {
    public let scrollView: NSScrollView
    let textView: BlockTextView
    public internal(set) var document: EditorDocument
    /// Wird nach jeder Änderung des Dokuments aufgerufen.
    public var onChange: ((EditorDocument) -> Void)?
    /// ↑ in der ersten Zeile: Fokus zurück in den Titel.
    public var onExitTop: (() -> Void)?
    /// Eigener Undo-Stapel pro Editor. `load` leert nur ihn, nicht das Undo des
    /// Fensters (Sidebar-Aktionen).
    let undoManager = UndoManager()
    /// Undo/Redo-Beobachter (`+Sync`); enden mit dem Controller.
    var undoObservations: [NotificationObservation] = []

    private let layoutDelegate = BlockLayoutDelegate()
    /// Startposition jedes Absatzes im Textspeicher; letzter Eintrag = Gesamtlänge.
    var paragraphStarts: [Int] = []
    /// Gesetzt, während der Controller selbst in den Textspeicher schreibt.
    var isApplying = false
    /// Zuletzt getippter Text, für Markdown-Kürzel und Slash-Menü.
    var lastInsertedString: String?
    /// Von der Text-View bearbeiteter Bereich seit dem letzten Abgleich.
    var editedRange: NSRange?
    var editedDelta = 0
    lazy var slashMenu = SlashMenuController(editor: self)
    /// Letzter Klick auf ＋, solange Escape ihn noch zurücknehmen kann.
    var pendingInsert: PendingInsert?
    /// Quelle der Bilder (Laden, Import, Kopien); ohne Store keine Bilder.
    public var imageStore: PageStore? {
        didSet { loadMissingImages() }
    }
    /// Bilder, die gerade geladen werden.
    var loadingImages: Set<UUID> = []
    /// Eingefügte Bilder, deren Import noch läuft; ihr Block zeigt den Platzhalter.
    var pendingImports: Set<UUID> = []
    lazy var noticeView = EditorNoticeView()

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
        textView.setAccessibilityIdentifier("editor.text")
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
        let text = BlockRenderer.render(document.blocks[...], ordinals: ordinals)
        isApplying = true
        textView.textStorage?.setAttributedString(text)
        isApplying = false
        rebuildParagraphStarts()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        updateTypingAttributes(forCaretAt: BlockPosition(block: 0, offset: 0))
        loadMissingImages()
    }

    /// Ersetzt das gesamte Dokument (z. B. Laden einer anderen Seite). Leert Undo.
    public func load(_ newDocument: EditorDocument) {
        slashMenu.close()
        document = newDocument
        loadStorage()
        textView.undoManager?.removeAllActions()
    }

    /// Macht den Editor zum Ersthelfer seines Fensters.
    public func focus() {
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: Positionen

    func rebuildParagraphStarts() {
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

    func paragraphRange(ofBlock index: Int) -> NSRange {
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
        let replacement = BlockRenderer.render(new[prefix..<(new.count - suffix)], ordinals: ordinals)

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
            updateTypingAttributes(forCaretAt: cursor)
        }
        loadMissingImages()
        onChange?(document)
    }

    /// Tipp-Attribute am Cursor: Blockart des Cursor-Blocks, Inline-Stil des Zeichens
    /// davor (am Blockanfang unformatiert). Die Text-View würde sonst am Blockanfang
    /// die Attribute des vorherigen Blocks übernehmen.
    func updateTypingAttributes(forCaretAt cursor: BlockPosition) {
        let block = document[cursor.block]
        var attributes = BlockStyle.attributes(for: block, ordinal: nil)
        if cursor.offset > 0, block.kind.allowsInlineMarks {
            let style = block.content.style(at: cursor.offset - 1)
            // Links setzen sich beim Weitertippen nicht fort.
            let inline = InlineStyle(marks: style.marks)
            attributes.merge(BlockStyle.inlineAttributes(for: inline, kind: block.kind)) { $1 }
        }
        textView.typingAttributes = attributes
    }

    /// Nummern nummerierter Punkte nachführen (nicht undo-relevant, abgeleitet).
    func refreshOrdinals() {
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

    // MARK: Hilfen für Slash-Menü und Text-View

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

/// Namen der Undo-Schritte („Widerrufen: …“).
enum UndoAction {
    static var typing: String { String(localized: "Tippen", bundle: .module) }
    static var newBlock: String { String(localized: "Neuer Block", bundle: .module) }
    static var indent: String { String(localized: "Einrücken", bundle: .module) }
    static var outdent: String { String(localized: "Ausrücken", bundle: .module) }
    static var delete: String { String(localized: "Löschen", bundle: .module) }
    static var markdownShortcut: String { String(localized: "Markdown-Kürzel", bundle: .module) }
    static var toggleChecked: String { String(localized: "Abhaken", bundle: .module) }
    static var changeKind: String { String(localized: "Blockart ändern", bundle: .module) }
    static var moveBlocks: String { String(localized: "Blöcke verschieben", bundle: .module) }
    static var duplicate: String { String(localized: "Duplizieren", bundle: .module) }
    static var cut: String { String(localized: "Ausschneiden", bundle: .module) }
    static var paste: String { String(localized: "Einsetzen", bundle: .module) }
    static var format: String { String(localized: "Formatieren", bundle: .module) }
    static var link: String { String(localized: "Link", bundle: .module) }
    static var insertImage: String { String(localized: "Bild einfügen", bundle: .module) }
}
#endif
