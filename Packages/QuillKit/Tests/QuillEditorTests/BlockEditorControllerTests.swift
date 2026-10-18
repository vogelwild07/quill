#if canImport(AppKit)
import AppKit
import QuillDesign
import QuillModel
import Testing
@testable import QuillEditor

/// Steuert Controller und Text-View wie Tastatureingaben, in einem Offscreen-Fenster.
@MainActor
private final class Harness {
    let window: NSWindow
    let editor: BlockEditorController
    var textView: NSTextView { editor.textView }

    init(_ blocks: [EditorBlock] = [EditorBlock()]) {
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        editor = BlockEditorController(document: EditorDocument(blocks: blocks))
        window.contentView = editor.scrollView
        editor.focus()
    }

    var document: EditorDocument { editor.document }
    var texts: [String] { document.blocks.map(\.text) }
    var kinds: [BlockKind] { document.blocks.map(\.kind) }
    var storage: String { textView.string }

    func caret(at block: Int, _ offset: Int) {
        let location = editor.characterLocation(of: BlockPosition(block: block, offset: offset))
        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    /// Jedes Zeichen ist wie in der App ein eigenes Tastaturereignis.
    func type(_ text: String) {
        for character in text {
            textView.insertText(String(character), replacementRange: textView.selectedRange())
            RunLoop.current.run(until: Date())
        }
    }

    func press(_ selector: Selector) {
        textView.doCommand(by: selector)
    }

    var caretPosition: BlockPosition { editor.position(atCharacter: textView.selectedRange().location) }

    func undo() {
        flushUndoGroup()
        textView.undoManager?.undo()
    }

    func redo() {
        flushUndoGroup()
        textView.undoManager?.redo()
    }

    /// Schließt die automatische Undo-Gruppe wie am Ende eines Ereignisses.
    func flushUndoGroup() {
        textView.breakUndoCoalescing()
        RunLoop.current.run(until: Date())
    }

    /// Invariante: Textspeicher entspricht dem Modell.
    func expectConsistent(sourceLocation: SourceLocation = #_sourceLocation) {
        let (parsed, repaired) = BlockRenderer.parse(textView.textStorage!)
        #expect(parsed == document.blocks, sourceLocation: sourceLocation)
        #expect(repaired.isEmpty, sourceLocation: sourceLocation)
        #expect(storage.hasSuffix("\n"), sourceLocation: sourceLocation)
    }
}

@MainActor
@Suite("Editor: Tippen und Struktur", .serialized)
struct TypingTests {
    @Test func typingUpdatesModel() {
        let h = Harness()
        h.type("Hallo")
        #expect(h.texts == ["Hallo"])
        h.expectConsistent()
    }

    @Test func enterSplitsAndBackspaceMerges() {
        let h = Harness([EditorBlock(text: "HalloWelt")])
        h.caret(at: 0, 5)
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.texts == ["Hallo", "Welt"])
        #expect(h.caretPosition == BlockPosition(block: 1, offset: 0))
        h.press(#selector(NSResponder.deleteBackward(_:)))
        #expect(h.texts == ["HalloWelt"])
        #expect(h.caretPosition == BlockPosition(block: 0, offset: 5))
        h.expectConsistent()
    }

    @Test func undoAndRedoRestoreStructure() {
        let h = Harness([EditorBlock(kind: .bulleted, text: "AB")])
        h.caret(at: 0, 1)
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.texts == ["A", "B"])
        h.undo()
        #expect(h.texts == ["AB"])
        #expect(h.kinds == [.bulleted])
        h.expectConsistent()
        h.redo()
        #expect(h.texts == ["A", "B"])
        #expect(h.kinds == [.bulleted, .bulleted])
        h.expectConsistent()
    }

    @Test func blockIDsSurviveUndo() {
        let first = EditorBlock(text: "Eins")
        let h = Harness([first, EditorBlock(text: "Zwei")])
        h.caret(at: 1, 0)
        h.press(#selector(NSResponder.deleteBackward(_:)))
        #expect(h.texts == ["EinsZwei"])
        h.undo()
        #expect(h.texts == ["Eins", "Zwei"])
        #expect(h.document[0].id == first.id)
        h.expectConsistent()
    }

    @Test func tabIndentsAndShiftTabOutdents() {
        let h = Harness([EditorBlock(kind: .bulleted, text: "A"), EditorBlock(kind: .bulleted, text: "B")])
        h.caret(at: 1, 1)
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(h.document[1].indent == 1)
        #expect(h.caretPosition == BlockPosition(block: 1, offset: 1))
        h.press(#selector(NSResponder.insertBacktab(_:)))
        #expect(h.document[1].indent == 0)
        h.expectConsistent()
    }

    @Test func softLineBreakStaysInBlock() {
        let h = Harness([EditorBlock(kind: .code, text: "a")])
        h.caret(at: 0, 1)
        h.press(#selector(NSResponder.insertNewline(_:)))
        h.type("b")
        #expect(h.document.count == 1)
        #expect(h.texts == ["a\nb"])
        h.expectConsistent()
    }

    @Test func selectionAcrossBlocksIsReplacedByTyping() {
        let h = Harness([EditorBlock(text: "Hallo"), EditorBlock(kind: .heading1, text: "mitte"), EditorBlock(text: "Welt")])
        let start = h.editor.characterLocation(of: BlockPosition(block: 0, offset: 2))
        let end = h.editor.characterLocation(of: BlockPosition(block: 2, offset: 1))
        h.textView.setSelectedRange(NSRange(location: start, length: end - start))
        h.type("X")
        #expect(h.texts == ["HaXelt"])
        h.expectConsistent()
    }

    @Test func caretNeverPassesFinalNewline() {
        let h = Harness([EditorBlock(text: "A")])
        h.textView.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(h.textView.selectedRange().location == 1)
    }

    @Test func pastingLinesCreatesBlocks() {
        let h = Harness()
        h.textView.insertText("eins\nzwei\ndrei", replacementRange: h.textView.selectedRange())
        #expect(h.texts == ["eins", "zwei", "drei"])
        h.expectConsistent()
    }

    @Test func imeCompositionIsLeftToTextView() {
        let h = Harness([EditorBlock(text: "")])
        h.textView.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        h.textView.setMarkedText("かん", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        h.textView.insertText("漢", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(h.texts == ["漢"])
        h.expectConsistent()
    }

    /// Neuladen aus einem anderen Fenster greift nie in eine laufende IME-Eingabe ein.
    @Test func reloadIsRejectedDuringComposition() {
        let h = Harness([EditorBlock(text: "")])
        h.textView.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(h.editor.reload(EditorDocument(blocks: [EditorBlock(text: "fremd")])) == false)
        #expect(h.textView.hasMarkedText())

        h.textView.insertText("漢", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(h.editor.reload(EditorDocument(blocks: [EditorBlock(text: "fremd")])))
        #expect(h.texts == ["fremd"])
        h.expectConsistent()
    }
}

@MainActor
@Suite("Editor: Markdown-Kürzel", .serialized)
struct ShortcutIntegrationTests {
    @Test(arguments: [
        ("# ", BlockKind.heading1), ("## ", .heading2), ("### ", .heading3), ("- ", .bulleted),
        ("1. ", .numbered), ("[] ", .todo), ("> ", .quote), ("``` ", .code),
    ])
    func convertsWhileTyping(prefix: String, kind: BlockKind) {
        let h = Harness()
        h.type(prefix + "x")
        #expect(h.kinds == [kind])
        #expect(h.texts == ["x"])
        h.expectConsistent()
    }

    @Test func dividerFromTripleDash() {
        let h = Harness()
        h.type("---")
        #expect(h.kinds == [.divider, .paragraph])
        #expect(h.caretPosition == BlockPosition(block: 1, offset: 0))
        h.expectConsistent()
    }

    @Test func undoRevertsShortcutOnly() {
        let h = Harness()
        h.type("# ")
        #expect(h.kinds == [.heading1])
        h.undo()
        #expect(h.kinds == [.paragraph])
        #expect(h.texts == ["# "])
        h.expectConsistent()
        h.redo()
        #expect(h.kinds == [.heading1])
        #expect(h.texts == [""])
    }

    @Test func numberedListCountsUp() {
        let h = Harness()
        h.type("1. a")
        h.press(#selector(NSResponder.insertNewline(_:)))
        h.type("b")
        let ordinals = BlockRenderer.ordinals(for: h.document)
        #expect(h.document.blocks.map { ordinals[$0.id] } == [1, 2])
        let stored = h.textView.textStorage!.attribute(.quillOrdinal, at: h.editor.characterLocation(of: BlockPosition(block: 1, offset: 0)), effectiveRange: nil) as? Int
        #expect(stored == 2)
    }
}

@MainActor
@Suite("Editor: Slash-Menü", .serialized)
struct SlashMenuIntegrationTests {
    @Test func filtersAndChoosesWithKeyboard() {
        let h = Harness([EditorBlock(text: "Ziele")])
        h.caret(at: 0, 5)
        h.press(#selector(NSResponder.insertNewline(_:)))
        h.type("/üb")
        h.press(#selector(NSResponder.moveDown(_:)))
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.kinds == [.paragraph, .heading2])
        #expect(h.texts == ["Ziele", ""])
        h.expectConsistent()
    }

    /// Nicht nur im letzten Block: Die Auswahl ändert sich vor dem Abgleich der Absätze.
    @Test func staysOpenWhileTypingInMiddleBlock() {
        let h = Harness([EditorBlock(text: "Eins"), EditorBlock(text: "Zwei")])
        h.caret(at: 0, 4)
        h.press(#selector(NSResponder.insertNewline(_:)))
        h.type("/üb")
        #expect(h.editor.slashMenu.isVisible)
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.kinds == [.paragraph, .heading1, .paragraph])
        #expect(h.texts == ["Eins", "", "Zwei"])
        h.expectConsistent()
    }

    @Test func escapeClosesAndKeepsText() {
        let h = Harness()
        h.type("/h")
        h.press(#selector(NSResponder.cancelOperation(_:)))
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.texts == ["/h", ""])
    }

    @Test func losingFocusCloses() {
        let h = Harness()
        h.type("/")
        #expect(h.editor.slashMenu.isVisible)
        h.window.makeFirstResponder(nil)
        #expect(!h.editor.slashMenu.isVisible)
    }

    @Test func arrowsWrapAround() {
        let h = Harness()
        h.type("/")
        h.press(#selector(NSResponder.moveUp(_:)))
        #expect(h.editor.slashMenu.selection == SlashCommand.all.count - 1)
        h.press(#selector(NSResponder.moveDown(_:)))
        #expect(h.editor.slashMenu.selection == 0)
    }

    @Test func slashInsideWordDoesNotOpen() {
        let h = Harness()
        h.type("und/oder")
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.texts == ["und/oder", ""])
    }
}

@MainActor
@Suite("Editor: Blockart per Menü und ⌘↩", .serialized)
struct BlockKindCommandTests {
    @Test func menuConvertsAllSelectedBlocksInOneStep() {
        let h = Harness([EditorBlock(text: "Eins"), EditorBlock(kind: .divider), EditorBlock(text: "Zwei"), EditorBlock(text: "Drei")])
        let start = h.editor.characterLocation(of: BlockPosition(block: 0, offset: 1))
        let end = h.editor.characterLocation(of: BlockPosition(block: 2, offset: 2))
        h.textView.setSelectedRange(NSRange(location: start, length: end - start))
        // Wie die Menüleiste: über die Responder-Kette.
        #expect(NSApp.sendAction(#selector(EditorFormattingActions.quillSetBlockKind(_:)), to: h.textView, from: BlockKindRequest(.todo)))
        #expect(h.kinds == [.todo, .divider, .todo, .paragraph])
        #expect(h.textView.selectedRange() == NSRange(location: start, length: end - start))
        h.undo()
        #expect(h.kinds == [.paragraph, .divider, .paragraph, .paragraph])
        h.expectConsistent()
    }

    @Test func menuWithoutSelectionConvertsBlockAtCursor() {
        let h = Harness([EditorBlock(text: "Eins"), EditorBlock(text: "Zwei")])
        h.caret(at: 1, 2)
        h.editor.convertSelectedBlocks(to: .heading2)
        #expect(h.kinds == [.paragraph, .heading2])
        #expect(h.caretPosition == BlockPosition(block: 1, offset: 2))
    }

    @Test func commandReturnTogglesTodos() {
        let h = Harness([EditorBlock(kind: .todo, text: "A"), EditorBlock(kind: .todo, text: "B", isChecked: true), EditorBlock(text: "C")])
        h.textView.setSelectedRange(NSRange(location: 0, length: h.editor.characterLocation(of: BlockPosition(block: 2, offset: 1))))
        h.editor.toggleCheckedInSelection()
        // Gemischt: alle abhaken; Absatz bleibt Absatz.
        #expect(h.document.blocks.map(\.isChecked) == [true, true, false])
        h.flushUndoGroup()
        h.editor.toggleCheckedInSelection()
        #expect(h.document.blocks.map(\.isChecked) == [false, false, false])
        h.undo()
        #expect(h.document.blocks.map(\.isChecked) == [true, true, false])
    }

    @Test func shortcutsAreUniqueAndSkipZoom() {
        let digits = BlockConversion.commands.compactMap { BlockConversion.shortcutDigit(for: $0.kind) }
        #expect(digits == ["0", "1", "2", "3", "4", "5", "6", "7"])
        #expect(!digits.contains("8"))
        #expect(BlockConversion.commands.map(\.kind) == [.paragraph, .heading1, .heading2, .heading3, .bulleted, .numbered, .todo, .quote, .code])
    }
}

@MainActor
@Suite("Editor: Block-Aktionen (Verschieben, Duplizieren, Löschen, Griff)", .serialized)
struct BlockActionTests {
    private func abc() -> Harness {
        Harness([EditorBlock(text: "A"), EditorBlock(text: "Bb"), EditorBlock(text: "C")])
    }

    /// CLAUDE.md: bei markiertem Text (IME, tote Tasten) nie eingreifen.
    @Test func blockActionsLeaveMarkedTextAlone() {
        let actions: [(String, (Harness) -> Void)] = [
            ("Duplizieren", { $0.editor.duplicateSelectedBlocks() }),
            ("Löschen", { $0.editor.deleteSelectedBlocks() }),
            ("Abhaken", { $0.editor.toggleCheckedInSelection() }),
            ("Verschieben", { _ = $0.editor.moveSelectedBlocks(by: 1) }),
            ("Umwandeln", { $0.editor.convertSelectedBlocks(to: .heading1) }),
            ("Griff", { h in
                h.editor.textView.handle.characterOffset = 0
                #expect(!h.editor.textView.handle.perform { $0.deleteSelectedBlocks() })
            }),
        ]
        for (name, action) in actions {
            let h = Harness([EditorBlock(kind: .todo, text: "A"), EditorBlock(text: "B")])
            h.caret(at: 0, 1)
            h.textView.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            let storage = h.textView.string
            action(h)
            #expect(h.textView.hasMarkedText(), "\(name)")
            #expect(h.textView.string == storage, "\(name)")
            #expect(h.kinds == [.todo, .paragraph], "\(name)")
            #expect(!h.document[0].isChecked, "\(name)")
        }
    }

    /// Hinter einem Trenner am Ende steht immer ein Absatz zum Weiterschreiben.
    @Test func blockActionsKeepEditableEnd() {
        let moved = Harness([EditorBlock(kind: .divider), EditorBlock(text: "A")])
        moved.caret(at: 1, 1)
        #expect(moved.editor.moveSelectedBlocks(by: -1))
        #expect(moved.kinds == [.paragraph, .divider, .paragraph])

        let deleted = Harness([EditorBlock(text: "A"), EditorBlock(kind: .divider), EditorBlock(text: "B")])
        deleted.caret(at: 2, 1)
        deleted.editor.deleteSelectedBlocks()
        #expect(deleted.kinds == [.paragraph, .divider, .paragraph])
        #expect(deleted.texts == ["A", "", ""])
        moved.expectConsistent()
        deleted.expectConsistent()
    }

    @Test func moveWithKeyboardKeepsCaret() {
        let h = abc()
        h.caret(at: 1, 1)
        #expect(h.editor.moveSelectedBlocks(by: -1))
        #expect(h.texts == ["Bb", "A", "C"])
        #expect(h.caretPosition == BlockPosition(block: 0, offset: 1))
        #expect(!h.editor.moveSelectedBlocks(by: -1))
        h.flushUndoGroup()
        #expect(h.editor.moveSelectedBlocks(by: 1))
        h.flushUndoGroup()
        #expect(h.editor.moveSelectedBlocks(by: 1))
        #expect(h.texts == ["A", "C", "Bb"])
        #expect(!h.editor.moveSelectedBlocks(by: 1))
        h.undo()
        #expect(h.texts == ["A", "Bb", "C"])
        h.expectConsistent()
    }

    @Test func moveSelectionMovesAllItsBlocks() {
        let h = abc()
        let start = h.editor.characterLocation(of: BlockPosition(block: 0, offset: 0))
        let end = h.editor.characterLocation(of: BlockPosition(block: 1, offset: 1))
        h.textView.setSelectedRange(NSRange(location: start, length: end - start))
        #expect(h.editor.moveSelectedBlocks(by: 1))
        #expect(h.texts == ["C", "A", "Bb"])
        #expect(h.textView.selectedRange().length == end - start)
    }

    @Test func dividerMovedToEndGetsParagraphAfter() {
        let h = Harness([EditorBlock(kind: .divider), EditorBlock(text: "A")])
        h.caret(at: 0, 0)
        #expect(h.editor.moveSelectedBlocks(by: 1))
        #expect(h.kinds == [.paragraph, .divider, .paragraph])
        h.expectConsistent()
    }

    @Test func duplicateInsertsCopyBelowAndSelectsIt() {
        let h = abc()
        h.caret(at: 1, 0)
        h.editor.duplicateSelectedBlocks()
        #expect(h.texts == ["A", "Bb", "Bb", "C"])
        #expect(h.document[1].id != h.document[2].id)
        let copy = h.editor.characterLocation(of: BlockPosition(block: 2, offset: 0))
        #expect(h.textView.selectedRange() == NSRange(location: copy, length: 2))
        h.undo()
        #expect(h.texts == ["A", "Bb", "C"])
        h.expectConsistent()
    }

    @Test func deleteRemovesBlocksAndNeverEmptiesDocument() {
        let h = abc()
        h.textView.setSelectedRange(NSRange(location: 0, length: h.editor.characterLocation(of: BlockPosition(block: 1, offset: 1))))
        h.editor.deleteSelectedBlocks()
        #expect(h.texts == ["C"])
        h.flushUndoGroup()
        h.textView.setSelectedRange(NSRange(location: 0, length: 1))
        h.editor.deleteSelectedBlocks()
        #expect(h.texts == [""])
        #expect(h.kinds == [.paragraph])
        h.undo()
        #expect(h.texts == ["C"])
        h.expectConsistent()
    }

    @Test func handleClickSelectsItsBlock() {
        let h = abc()
        let handle = h.editor.textView.handle
        handle.characterOffset = h.editor.characterLocation(of: BlockPosition(block: 1, offset: 0))
        handle.perform { _ in }
        #expect(h.textView.selectedRange() == NSRange(location: handle.characterOffset, length: 2))
    }

    @Test func contextMenuConvertsAndDuplicatesHandleBlock() throws {
        let h = abc()
        let handle = h.editor.textView.handle
        handle.characterOffset = h.editor.characterLocation(of: BlockPosition(block: 2, offset: 0))
        let menu = handle.makeMenu()
        #expect(menu.items.map(\.title) == ["Löschen", "Duplizieren", "", "Umwandeln in"])
        #expect(menu.items[1].keyEquivalent == "d")
        let submenu = try #require(menu.items[3].submenu)
        #expect(submenu.items.map(\.title) == BlockConversion.commands.map(\.title))
        #expect(submenu.items[1].keyEquivalent == "1" && submenu.items[1].keyEquivalentModifierMask == [.command, .option])

        submenu.performActionForItem(at: 6)
        #expect(h.kinds == [.paragraph, .paragraph, .todo])
        menu.performActionForItem(at: 1)
        #expect(h.texts == ["A", "Bb", "C", "C"])
        #expect(h.kinds == [.paragraph, .paragraph, .todo, .todo])
        menu.performActionForItem(at: 0)
        h.expectConsistent()
    }

    @Test func handleOffersAccessibilityActions() {
        let h = abc()
        let handle = h.editor.textView.handle
        let names = (handle.accessibilityCustomActions() ?? []).map(\.name)
        #expect(names == ["Nach oben verschieben", "Nach unten verschieben", "Duplizieren", "Löschen"])
        handle.characterOffset = h.editor.characterLocation(of: BlockPosition(block: 2, offset: 0))
        _ = handle.accessibilityCustomActions()?.first?.handler?()
        #expect(h.texts == ["A", "C", "Bb"])
    }

    @Test func dropIndicatorStartsAtTargetIndent() {
        let h = Harness([EditorBlock(text: "A"), EditorBlock(kind: .bulleted, text: "B", indent: 1), EditorBlock(kind: .bulleted, text: "C")])
        let view = h.editor.textView
        let paragraph = view.dropIndicatorFrame(index: 0, y: 10)
        let nested = view.dropIndicatorFrame(index: 1, y: 10)
        let list = view.dropIndicatorFrame(index: 2, y: 10)
        #expect(nested.minX - list.minX == QuillDesign.Spacing.indentStep)
        #expect(list.minX == paragraph.minX)
        #expect(nested.maxX == paragraph.maxX)
    }

    @Test func dragNearBottomScrolls() {
        let h = Harness(SampleDocuments.large(blockCount: 300).blocks)
        let view = h.editor.textView
        view.layoutSubtreeIfNeeded()
        let before = view.visibleRect
        view.autoscrollForDrag(at: NSPoint(x: before.midX, y: before.maxY - 5))
        #expect(view.visibleRect.minY > before.minY)
        let after = view.visibleRect
        view.autoscrollForDrag(at: NSPoint(x: after.midX, y: after.midY))
        #expect(view.visibleRect.minY == after.minY)
        view.autoscrollForDrag(at: NSPoint(x: after.midX, y: after.minY + 5))
        #expect(view.visibleRect.minY < after.minY)
    }
}

@MainActor
@Suite("Editor: Einfügen-Knopf ＋", .serialized)
struct InsertButtonTests {
    private func location(_ h: Harness, _ block: Int) -> Int {
        h.editor.characterLocation(of: BlockPosition(block: block, offset: 1))
    }

    @Test func insertsBelowWithOpenSlashMenu() {
        let h = Harness([EditorBlock(text: "Eins"), EditorBlock(text: "Zwei")])
        h.editor.insertBlockWithMenu(nearCharacter: location(h, 0), above: false)
        #expect(h.texts == ["Eins", "/", "Zwei"])
        #expect(h.caretPosition == BlockPosition(block: 1, offset: 1))
        #expect(h.editor.slashMenu.isVisible)

        h.type("üb")
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.kinds == [.paragraph, .heading1, .paragraph])
        #expect(h.texts == ["Eins", "", "Zwei"])
        h.expectConsistent()
    }

    @Test func optionInsertsAbove() {
        let h = Harness([EditorBlock(text: "Eins"), EditorBlock(text: "Zwei")])
        h.editor.insertBlockWithMenu(nearCharacter: location(h, 0), above: true)
        #expect(h.texts == ["/", "Eins", "Zwei"])
        #expect(h.editor.slashMenu.isVisible)
        h.expectConsistent()
    }

    @Test func emptyParagraphIsUsedItself() {
        let h = Harness([EditorBlock(text: "Eins"), EditorBlock()])
        h.editor.insertBlockWithMenu(nearCharacter: h.editor.characterLocation(of: BlockPosition(block: 1, offset: 0)), above: false)
        #expect(h.texts == ["Eins", "/"])
        #expect(h.editor.slashMenu.isVisible)
    }

    @Test func isOneUndoStep() {
        let h = Harness([EditorBlock(text: "Eins"), EditorBlock(text: "Zwei")])
        h.editor.insertBlockWithMenu(nearCharacter: location(h, 1), above: false)
        // Menü schließt ohne Escape (z. B. Klick woanders): „/“ bleibt, Undo nimmt alles.
        h.editor.slashMenu.close()
        #expect(h.texts == ["Eins", "Zwei", "/"])
        h.undo()
        #expect(h.texts == ["Eins", "Zwei"])
        h.redo()
        #expect(h.texts == ["Eins", "Zwei", "/"])
        h.expectConsistent()
    }

    @Test func escapeRemovesInsertedBlock() {
        let h = Harness([EditorBlock(text: "Eins"), EditorBlock(text: "Zwei")])
        h.caret(at: 1, 2)
        h.editor.insertBlockWithMenu(nearCharacter: location(h, 0), above: false)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.texts == ["Eins", "Zwei"])
        #expect(!h.editor.slashMenu.isVisible)
        #expect(h.caretPosition == BlockPosition(block: 1, offset: 2))
        // Kein Rest im Undo-Verlauf.
        h.undo()
        #expect(h.texts == ["Eins", "Zwei"])
        h.expectConsistent()
    }

    @Test func escapeAfterFilterRemovesBlockAndFilter() {
        let h = Harness([EditorBlock(text: "Eins"), EditorBlock(text: "Zwei")])
        h.editor.insertBlockWithMenu(nearCharacter: location(h, 0), above: true)
        h.type("üb")
        #expect(h.texts == ["/üb", "Eins", "Zwei"])
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.texts == ["Eins", "Zwei"])
        h.expectConsistent()
    }

    @Test func escapeKeepsReusedEmptyParagraphEmpty() {
        let h = Harness([EditorBlock(text: "Eins"), EditorBlock()])
        h.editor.insertBlockWithMenu(nearCharacter: h.editor.characterLocation(of: BlockPosition(block: 1, offset: 0)), above: false)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.texts == ["Eins", ""])
        #expect(h.kinds == [.paragraph, .paragraph])
        h.expectConsistent()
    }

    @Test func escapeDoesNotUndoEarlierTyping() {
        let h = Harness([EditorBlock(text: "Eins")])
        h.caret(at: 0, 4)
        h.type("!")
        h.flushUndoGroup()
        h.editor.insertBlockWithMenu(nearCharacter: location(h, 0), above: false)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.texts == ["Eins!"])
    }

    @Test func escapeAfterMenuClosedWithoutMatchesStillReverts() {
        let h = Harness([EditorBlock(text: "Eins"), EditorBlock(text: "Zwei")])
        h.editor.insertBlockWithMenu(nearCharacter: location(h, 0), above: false)
        h.type("abcd")
        #expect(!h.editor.slashMenu.isVisible)
        #expect(h.texts == ["Eins", "/abcd", "Zwei"])
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.texts == ["Eins", "Zwei"])
        h.expectConsistent()
    }

    @Test func escapeAfterLeavingTheBlockKeepsIt() {
        let h = Harness([EditorBlock(text: "Eins"), EditorBlock(text: "Zwei")])
        h.editor.insertBlockWithMenu(nearCharacter: location(h, 0), above: false)
        h.type("abcd")
        h.caret(at: 0, 2)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.texts == ["Eins", "/abcd", "Zwei"])
    }

    @Test func escapeAfterChoosingKeepsBlock() {
        let h = Harness([EditorBlock(text: "Eins")])
        h.editor.insertBlockWithMenu(nearCharacter: location(h, 0), above: false)
        h.type("üb")
        h.press(#selector(NSResponder.insertNewline(_:)))
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.kinds == [.paragraph, .heading1])
    }

    /// Ein fremder Schritt liegt über „Neuer Block“ (z. B. ein Import im Hintergrund):
    /// Escape entfernt den Block als eigene Bearbeitung und lässt den Schritt stehen.
    @Test func escapeWithForeignStepOnTopUndoesNothingElse() {
        let h = Harness([EditorBlock(kind: .todo, text: "Aufgabe"), EditorBlock(text: "Zwei")])
        h.editor.insertBlockWithMenu(nearCharacter: location(h, 1), above: false)
        h.flushUndoGroup()
        h.editor.toggleChecked(atCharacter: location(h, 0))
        h.flushUndoGroup()
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.texts == ["Aufgabe", "Zwei"])
        #expect(h.document[0].isChecked)
        h.flushUndoGroup()
        h.undo()
        #expect(h.texts == ["Aufgabe", "Zwei", "/"])
        #expect(h.document[0].isChecked)
        h.expectConsistent()
    }

    @Test func escapeWithFilterAndForeignStepKeepsReusedParagraphEmpty() {
        let h = Harness([EditorBlock(kind: .todo, text: "Aufgabe"), EditorBlock()])
        h.editor.insertBlockWithMenu(nearCharacter: h.editor.characterLocation(of: BlockPosition(block: 1, offset: 0)), above: false)
        h.type("ü")
        h.flushUndoGroup()
        h.editor.toggleChecked(atCharacter: location(h, 0))
        h.flushUndoGroup()
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.texts == ["Aufgabe", ""])
        #expect(h.document[0].isChecked)
        h.expectConsistent()
    }

    @Test func buttonActsOnItsBlock() {
        let h = Harness([EditorBlock(text: "Eins"), EditorBlock(kind: .divider), EditorBlock(text: "Zwei")])
        let button = h.editor.textView.insertButton
        button.characterOffset = h.editor.characterLocation(of: BlockPosition(block: 1, offset: 0))
        #expect(button.accessibilityPerformPress())
        #expect(h.kinds == [.paragraph, .divider, .paragraph, .paragraph])
        #expect(h.texts == ["Eins", "", "/", "Zwei"])
        #expect(button.accessibilityLabel() == "Block einfügen")
    }
}

@MainActor
@Suite("Editor: Zwischenablage, Verschieben, Checkbox", .serialized)
struct ClipboardAndMoveTests {
    /// Eigenes Pasteboard pro Test; mit `defer { board.releaseGlobally() }` freigeben.
    private func pasteboard() -> NSPasteboard { NSPasteboard(name: .init("de.vogel.quill.tests.\(UUID().uuidString)")) }

    private func sample() -> Harness {
        Harness(SampleDocuments.mixed)
    }

    @Test func copyWritesAllRepresentations() throws {
        let h = sample()
        let start = h.editor.characterLocation(of: BlockPosition(block: 0, offset: 2))
        let end = h.editor.characterLocation(of: BlockPosition(block: 2, offset: 4))
        h.textView.setSelectedRange(NSRange(location: start, length: end - start))
        let board = pasteboard()
        defer { board.releaseGlobally() }
        #expect(h.editor.copySelection(to: board))

        let types = Set(board.pasteboardItems?.first?.types ?? [])
        #expect(types.isSuperset(of: [.string, .markdown, .rtf, .quillBlocks]))
        #expect(board.string(forType: .markdown) == "# tel\n\n- [x] Aufgabe\n1. eins")
        #expect(board.string(forType: .string) == "tel\nAufgabe\neins")
        let data = try #require(board.data(forType: .quillBlocks))
        let blocks = try #require(BlockClipboard.decode(data))
        #expect(blocks.map(\.kind) == [.heading1, .todo, .numbered])
    }

    @Test func pastingDividerAtEndKeepsEditableParagraph() throws {
        let h = Harness([EditorBlock(text: "A"), EditorBlock(kind: .divider), EditorBlock(text: "B")])
        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setData(try #require(BlockClipboard.encode([EditorBlock(kind: .divider), EditorBlock(kind: .divider)])), forType: .quillBlocks)
        h.caret(at: 2, 1)
        #expect(h.editor.paste(from: board))
        #expect(h.kinds == [.paragraph, .divider, .paragraph, .divider, .divider, .paragraph])
        #expect(h.caretPosition == BlockPosition(block: 5, offset: 0))
        h.expectConsistent()
    }

    @Test func pastingQuillBlocksKeepsKindsWithNewIDs() {
        let h = sample()
        let start = h.editor.characterLocation(of: BlockPosition(block: 1, offset: 0))
        let end = h.editor.characterLocation(of: BlockPosition(block: 2, offset: 4))
        h.textView.setSelectedRange(NSRange(location: start, length: end - start))
        let board = pasteboard()
        defer { board.releaseGlobally() }
        _ = h.editor.copySelection(to: board)
        h.caret(at: 3, 4)
        #expect(h.editor.paste(from: board))
        #expect(h.kinds == [.heading1, .todo, .numbered, .paragraph, .todo, .numbered])
        #expect(Set(h.document.blocks.map(\.id)).count == 6)
        h.expectConsistent()
    }

    @Test func pastingOlderQuillBlocksFallsBackToPlainText() {
        let h = sample()
        let board = pasteboard()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        let version1 = #"[{"id":"7A3B5B6E-6C2B-4C38-9E73-6C1C4D2E8F10","kind":"heading1","text":"alt","indent":0,"isChecked":false}]"#
        item.setData(Data(version1.utf8), forType: .quillBlocks)
        item.setString("alt", forType: .string)
        board.clearContents()
        board.writeObjects([item])
        h.caret(at: 3, 4)
        #expect(h.editor.paste(from: board))
        #expect(h.kinds == [.heading1, .todo, .numbered, .paragraph])
        #expect(h.texts[3] == "Endealt")
        h.expectConsistent()
    }

    @Test func movingBlocksIsUndoable() {
        let h = sample()
        let ids = [h.document[0].id, h.document[1].id]
        #expect(h.editor.moveBlocks(withIDs: ids, to: 4))
        #expect(h.texts == ["eins", "Ende", "Titel", "Aufgabe"])
        h.expectConsistent()
        h.undo()
        #expect(h.texts == ["Titel", "Aufgabe", "eins", "Ende"])
        h.expectConsistent()
    }

    @Test func movingOntoItselfDoesNothing() {
        let h = sample()
        #expect(!h.editor.moveBlocks(withIDs: [h.document[1].id], to: 2))
        #expect(!h.editor.moveBlocks(withIDs: [h.document[1].id], to: 1))
    }

    @Test func checkboxTogglesAndKeepsSelection() {
        let h = sample()
        h.caret(at: 3, 2)
        h.editor.toggleChecked(atCharacter: h.editor.characterLocation(of: BlockPosition(block: 1, offset: 0)))
        #expect(h.document[1].isChecked == false)
        #expect(h.caretPosition == BlockPosition(block: 3, offset: 2))
        h.expectConsistent()
    }

    @Test func dividerIsDeletedAsOneBlock() {
        let h = Harness([EditorBlock(text: "A"), EditorBlock(kind: .divider), EditorBlock(text: "B")])
        h.caret(at: 1, 1)
        h.press(#selector(NSResponder.deleteBackward(_:)))
        #expect(h.kinds == [.paragraph, .paragraph])
        #expect(h.texts == ["A", "B"])
        h.expectConsistent()
    }

    @Test func typingNextToDividerCreatesParagraph() {
        let h = Harness([EditorBlock(kind: .divider)])
        h.caret(at: 0, 1)
        h.type("x")
        #expect(h.kinds == [.divider, .paragraph])
        #expect(h.texts == ["", "x"])
        h.expectConsistent()
    }
}

@MainActor
@Suite("Editor: Inline-Formatierung", .serialized)
struct FormattingIntegrationTests {
    private func select(_ h: Harness, from start: BlockPosition, to end: BlockPosition) {
        let from = h.editor.characterLocation(of: start)
        let to = h.editor.characterLocation(of: end)
        h.textView.setSelectedRange(NSRange(location: from, length: to - from))
    }

    @Test func boldOnSelectionIsOneUndoStepAndKeepsSelection() {
        let h = Harness([EditorBlock(text: "Hallo Welt")])
        select(h, from: BlockPosition(block: 0, offset: 0), to: BlockPosition(block: 0, offset: 5))
        h.editor.toggleMark(.bold)
        #expect(h.document[0].spans == [InlineSpan(0..<5, marks: [.bold])])
        #expect(h.textView.selectedRange() == NSRange(location: 0, length: 5))
        let font = h.textView.textStorage!.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        h.expectConsistent()
        h.undo()
        #expect(h.document[0].spans.isEmpty)
        h.expectConsistent()
        h.redo()
        #expect(h.document[0].spans == [InlineSpan(0..<5, marks: [.bold])])
    }

    @Test func toggleOnFullyBoldSelectionRemovesBold() {
        let h = Harness([EditorBlock(text: "Hallo", spans: [InlineSpan(0..<5, marks: [.bold])])])
        select(h, from: BlockPosition(block: 0, offset: 1), to: BlockPosition(block: 0, offset: 3))
        h.editor.toggleMark(.bold)
        #expect(h.document[0].spans == [InlineSpan(0..<1, marks: [.bold]), InlineSpan(3..<5, marks: [.bold])])
        h.expectConsistent()
    }

    @Test func typingAfterBoldTextStaysBold() {
        let h = Harness([EditorBlock(text: "ab", spans: [InlineSpan(0..<2, marks: [.bold])])])
        h.caret(at: 0, 2)
        h.type("cd")
        #expect(h.document[0].spans == [InlineSpan(0..<4, marks: [.bold])])
        h.expectConsistent()
    }

    @Test func toggleWithoutSelectionChangesOnlyTypingAttributes() {
        let h = Harness([EditorBlock(text: "ab")])
        h.caret(at: 0, 2)
        h.editor.toggleMark(.italic)
        #expect(h.document[0].spans.isEmpty)
        h.type("cd")
        h.editor.toggleMark(.italic)
        h.type("e")
        #expect(h.document[0].text == "abcde")
        #expect(h.document[0].spans == [InlineSpan(2..<4, marks: [.italic])])
        h.expectConsistent()
    }

    @Test func enterInsideBoldKeepsBothHalvesBold() {
        let h = Harness([EditorBlock(text: "abcd", spans: [InlineSpan(0..<4, marks: [.bold])])])
        h.caret(at: 0, 2)
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.document.blocks.map(\.spans) == [[InlineSpan(0..<2, marks: [.bold])], [InlineSpan(0..<2, marks: [.bold])]])
        h.expectConsistent()
    }

    @Test func markdownShortcutKeepsInlineFormatting() {
        let h = Harness([EditorBlock(text: "Titel", spans: [InlineSpan(0..<5, marks: [.bold])])])
        h.caret(at: 0, 0)
        h.type("# ")
        #expect(h.kinds == [.heading1])
        #expect(h.document[0].spans == [InlineSpan(0..<5, marks: [.bold])])
        h.expectConsistent()
    }

    @Test func copyInsideOneBlockWritesInlineFormatsAndPastesInline() throws {
        let h = Harness([
            EditorBlock(text: "Hallo Welt", spans: [InlineSpan(6..<10, marks: [.bold])]),
            EditorBlock(kind: .heading1, text: "Ziel"),
        ])
        select(h, from: BlockPosition(block: 0, offset: 4), to: BlockPosition(block: 0, offset: 8))
        let board = NSPasteboard(name: .init("de.vogel.quill.tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        #expect(h.editor.copySelection(to: board))
        #expect(board.string(forType: .markdown) == "o **We**")
        #expect(board.string(forType: .string) == "o We")
        let rtf = try #require(board.data(forType: .rtf))
        let rich = try #require(NSAttributedString(rtf: rtf, documentAttributes: nil))
        let font = rich.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        h.caret(at: 1, 2)
        #expect(h.editor.paste(from: board))
        #expect(h.kinds == [.paragraph, .heading1])
        #expect(h.document[1].text == "Zio Weel")
        #expect(h.document[1].spans == [InlineSpan(4..<6, marks: [.bold])])
        h.expectConsistent()
    }

    @Test func linkCanBeSetChangedAndRemoved() {
        let h = Harness([EditorBlock(text: "siehe Quill")])
        select(h, from: BlockPosition(block: 0, offset: 6), to: BlockPosition(block: 0, offset: 11))
        let target = h.editor.linkTarget()
        #expect(target.link == nil)
        h.editor.setLink("https://quill.app", on: target.range)
        #expect(h.document[0].spans == [InlineSpan(6..<11, marks: [], link: "https://quill.app")])
        let stored = h.textView.textStorage!.attribute(.link, at: 7, effectiveRange: nil) as? URL
        #expect(stored == URL(string: "https://quill.app"))
        h.expectConsistent()
        h.flushUndoGroup()

        h.caret(at: 0, 8)
        let existing = h.editor.linkTarget()
        #expect(existing.link == "https://quill.app")
        #expect(existing.range.length == 5)
        h.editor.setLink(nil, on: existing.range)
        #expect(h.document[0].spans.isEmpty)
        h.undo()
        #expect(h.document[0].spans.first?.style.link == "https://quill.app")
        h.expectConsistent()
    }

    @Test func linkWithoutSelectionInsertsTheAddress() {
        let h = Harness([EditorBlock(text: "Web: ")])
        h.caret(at: 0, 5)
        let target = h.editor.linkTarget()
        h.editor.setLink(BlockEditorController.normalizedLink("quill.app"), on: target.range)
        #expect(h.document[0].text == "Web: https://quill.app")
        #expect(h.document[0].spans == [InlineSpan(5..<22, marks: [], link: "https://quill.app")])
        #expect(h.caretPosition == BlockPosition(block: 0, offset: 22))
        h.expectConsistent()
    }

    @Test func formattingIgnoresCodeBlocks() {
        let h = Harness([EditorBlock(kind: .code, text: "let a")])
        select(h, from: BlockPosition(block: 0, offset: 0), to: BlockPosition(block: 0, offset: 3))
        h.editor.toggleMark(.bold)
        #expect(h.document[0].spans.isEmpty)
    }
}

@MainActor
@Suite("Editor: Messung", .serialized)
struct PerformanceTests {
    /// ADR-007: Tippen bei 1000 Blöcken p95 < 16 ms (ein Frame). Im Release-Build
    /// liegt der Median unter 1 ms; die Schwelle gilt auch für Debug-Builds.
    @Test func typingStaysWithinOneFrameAt1000Blocks() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        let result = EditorBenchmark.run(in: window, blockCount: 1000, keystrokes: 200, enters: 50)
        #expect(result.blocks == 1050)
        #expect(result.typing.p95 < 16, "Tippen p95 \(result.typing.p95) ms")
        #expect(result.enter.p95 < 16, "Enter p95 \(result.enter.p95) ms")
        #expect(result.loadMilliseconds < 300, "Laden \(result.loadMilliseconds) ms")
    }
}
#endif
