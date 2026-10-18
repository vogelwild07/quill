import Foundation
import QuillModel
import Testing
@testable import QuillEditor

private func doc(_ blocks: EditorBlock...) -> EditorDocument { EditorDocument(blocks: blocks) }
private func pos(_ block: Int, _ offset: Int) -> BlockPosition { BlockPosition(block: block, offset: offset) }

@Suite("Enter")
struct SplitTests {
    @Test func splitsParagraphInTheMiddle() {
        var document = doc(EditorBlock(text: "Hallo Welt"))
        let cursor = document.splitBlock(at: pos(0, 5))
        #expect(document.blocks.map(\.text) == ["Hallo", " Welt"])
        #expect(cursor == pos(1, 0))
    }

    @Test func headingContinuesAsParagraph() {
        var document = doc(EditorBlock(kind: .heading1, text: "Titel"))
        document.splitBlock(at: pos(0, 5))
        #expect(document.blocks.map(\.kind) == [.heading1, .paragraph])
    }

    @Test func listContinuesWithSameKindAndIndent() {
        var document = doc(EditorBlock(kind: .todo, text: "A", indent: 2, isChecked: true))
        document.splitBlock(at: pos(0, 1))
        #expect(document[1].kind == .todo)
        #expect(document[1].indent == 2)
        #expect(document[1].isChecked == false)
    }

    @Test func enterAtStartInsertsEmptyBlockAboveAndKeepsIdentity() {
        let heading = EditorBlock(kind: .heading2, text: "Ziele")
        var document = doc(heading)
        let cursor = document.splitBlock(at: pos(0, 0))
        #expect(document.blocks.map(\.kind) == [.paragraph, .heading2])
        #expect(document[1].id == heading.id)
        #expect(cursor == pos(1, 0))
    }

    @Test func emptyListItemLeavesList() {
        var document = doc(EditorBlock(kind: .bulleted, text: "A"), EditorBlock(kind: .bulleted))
        let cursor = document.splitBlock(at: pos(1, 0))
        #expect(document.blocks.map(\.kind) == [.bulleted, .paragraph])
        #expect(cursor == pos(1, 0))
    }

    @Test func emptyIndentedListItemOutdentsFirst() {
        var document = doc(EditorBlock(kind: .bulleted, text: "A"), EditorBlock(kind: .bulleted, indent: 1))
        document.splitBlock(at: pos(1, 0))
        #expect(document[1].kind == .bulleted)
        #expect(document[1].indent == 0)
    }

    @Test func codeBlockInsertsSoftLineBreak() {
        var document = doc(EditorBlock(kind: .code, text: "let a"))
        let cursor = document.splitBlock(at: pos(0, 5))
        #expect(document.count == 1)
        #expect(document[0].text == "let a\n")
        #expect(cursor == pos(0, 6))
    }

    @Test func enterOnDividerAddsParagraphBelow() {
        var document = doc(EditorBlock(kind: .divider), EditorBlock(text: "x"))
        let cursor = document.splitBlock(at: pos(0, 0))
        #expect(document.blocks.map(\.kind) == [.divider, .paragraph, .paragraph])
        #expect(cursor == pos(1, 0))
    }

    @Test func splitsAtUTF16OffsetWithEmoji() {
        var document = doc(EditorBlock(text: "👍🏽ok"))
        let emojiLength = "👍🏽".utf16.count
        document.splitBlock(at: pos(0, emojiLength))
        #expect(document.blocks.map(\.text) == ["👍🏽", "ok"])
    }
}

@Suite("Backspace am Blockanfang")
struct BackspaceTests {
    @Test func listItemBecomesParagraphFirst() {
        var document = doc(EditorBlock(text: "A"), EditorBlock(kind: .bulleted, text: "B"))
        let cursor = document.deleteBackwardAtStart(of: 1)
        #expect(document.blocks.map(\.kind) == [.paragraph, .paragraph])
        #expect(document.count == 2)
        #expect(cursor == pos(1, 0))
    }

    @Test(arguments: [BlockKind.heading1, .heading2, .heading3, .quote, .todo, .numbered, .code])
    func textBlockBecomesParagraphKeepingText(kind: BlockKind) {
        var document = doc(EditorBlock(text: "A"), EditorBlock(kind: kind, text: "B"))
        let cursor = document.deleteBackwardAtStart(of: 1)
        #expect(document.blocks.map(\.kind) == [.paragraph, .paragraph])
        #expect(document.blocks.map(\.text) == ["A", "B"])
        #expect(cursor == pos(1, 0))
    }

    @Test func indentedParagraphOutdents() {
        var document = doc(EditorBlock(text: "A"), EditorBlock(text: "B", indent: 1))
        _ = document.deleteBackwardAtStart(of: 1)
        #expect(document[1].indent == 0)
        #expect(document.count == 2)
    }

    @Test func paragraphMergesIntoPrevious() {
        let first = EditorBlock(kind: .heading1, text: "Ab")
        var document = doc(first, EditorBlock(text: "cd"))
        let cursor = document.deleteBackwardAtStart(of: 1)
        #expect(document.count == 1)
        #expect(document[0].text == "Abcd")
        #expect(document[0].id == first.id)
        #expect(document[0].kind == .heading1)
        #expect(cursor == pos(0, 2))
    }

    @Test func removesPreviousDivider() {
        var document = doc(EditorBlock(text: "A"), EditorBlock(kind: .divider), EditorBlock(text: "B"))
        let cursor = document.deleteBackwardAtStart(of: 2)
        #expect(document.blocks.map(\.text) == ["A", "B"])
        #expect(cursor == pos(1, 0))
    }

    @Test func nothingAtDocumentStart() {
        var document = doc(EditorBlock(text: "A"))
        let cursor = document.deleteBackwardAtStart(of: 0)
        #expect(cursor == nil)
    }

    @Test func documentNeverBecomesEmpty() {
        var document = doc(EditorBlock(kind: .divider))
        document.deleteBlock(at: 0)
        #expect(document.count == 1)
        #expect(document[0].kind == .paragraph)
    }
}

@Suite("Text ersetzen")
struct ReplaceTests {
    @Test func pastingLinesCreatesParagraphs() {
        var document = doc(EditorBlock(kind: .bulleted, text: "AB"))
        let cursor = document.insertText("1\n2\n3", at: pos(0, 1))
        #expect(document.blocks.map(\.text) == ["A1", "2", "3B"])
        #expect(document[0].kind == .bulleted)
        #expect(cursor == pos(2, 1))
    }

    @Test func replacingAcrossBlocksMergesThem() {
        var document = doc(EditorBlock(text: "Hallo"), EditorBlock(text: "mitte"), EditorBlock(text: "Welt"))
        let cursor = document.replace(from: pos(0, 2), to: pos(2, 1), with: "X")
        #expect(document.blocks.map(\.text) == ["HaXelt"])
        #expect(cursor == pos(0, 3))
    }

    @Test func codeBlockKeepsLineBreaks() {
        var document = doc(EditorBlock(kind: .code, text: ""))
        document.insertText("a\nb", at: pos(0, 0))
        #expect(document.count == 1)
        #expect(document[0].text == "a\nb")
    }
}

@Suite("Einrückung")
struct IndentTests {
    @Test func indentIsLimitedByPreviousBlock() {
        var document = doc(EditorBlock(kind: .bulleted, text: "A"), EditorBlock(kind: .bulleted, text: "B"))
        let first = document.indent(at: 1)
        let second = document.indent(at: 1)
        #expect(first && !second)
        #expect(document[1].indent == 1)
    }

    @Test func firstBlockCannotIndent() {
        var document = doc(EditorBlock(kind: .bulleted, text: "A"))
        let changed = document.indent(at: 0)
        #expect(!changed)
    }

    @Test func headingsDoNotIndent() {
        var document = doc(EditorBlock(text: "A"), EditorBlock(kind: .heading1, text: "B"))
        let changed = document.indent(at: 1)
        #expect(!changed)
    }

    @Test func outdent() {
        var document = doc(EditorBlock(text: "A"), EditorBlock(text: "B", indent: 1))
        let first = document.outdent(at: 1)
        let second = document.outdent(at: 1)
        #expect(first && !second)
    }
}

@Suite("Markdown-Kürzel")
struct MarkdownShortcutTests {
    @Test(arguments: [
        ("# ", BlockKind.heading1), ("## ", .heading2), ("### ", .heading3),
        ("- ", .bulleted), ("* ", .bulleted), ("1. ", .numbered), ("12. ", .numbered),
        ("[] ", .todo), ("[ ] ", .todo), ("> ", .quote), ("``` ", .code),
    ])
    func convertsPrefix(prefix: String, kind: BlockKind) {
        var document = doc(EditorBlock(text: prefix))
        let cursor = document.applyMarkdownShortcut(at: pos(0, prefix.utf16.count))
        #expect(document[0].kind == kind)
        #expect(document[0].text == "")
        #expect(cursor == pos(0, 0))
    }

    @Test func keepsTextAfterCursor() {
        var document = doc(EditorBlock(text: "- Einkaufen"))
        _ = document.applyMarkdownShortcut(at: pos(0, 2))
        #expect(document[0].kind == .bulleted)
        #expect(document[0].text == "Einkaufen")
    }

    @Test func checkedTodo() {
        var document = doc(EditorBlock(text: "[x] "))
        _ = document.applyMarkdownShortcut(at: pos(0, 4))
        #expect(document[0].kind == .todo)
        #expect(document[0].isChecked)
    }

    @Test func codeFenceWithLanguage() {
        var document = doc(EditorBlock(text: "```swift "))
        _ = document.applyMarkdownShortcut(at: pos(0, 9))
        #expect(document[0].kind == .code)
        #expect(document[0].codeLanguage == "swift")
    }

    @Test func tripleDashBecomesDividerWithParagraphAfter() {
        var document = doc(EditorBlock(text: "---"))
        let cursor = document.applyMarkdownShortcut(at: pos(0, 3))
        #expect(document.blocks.map(\.kind) == [.divider, .paragraph])
        #expect(cursor == pos(1, 0))
    }

    @Test(arguments: ["#Titel", "a # ", "-- ", "1) ", "x. "])
    func ignoresNonShortcuts(text: String) {
        var document = doc(EditorBlock(text: text))
        let cursor = document.applyMarkdownShortcut(at: pos(0, text.utf16.count))
        #expect(cursor == nil)
        #expect(document[0].kind == .paragraph)
    }

    @Test(arguments: [
        (BlockKind.bulleted, "## ", BlockKind.heading2), (.heading1, "- ", .bulleted), (.todo, "> ", .quote),
        (.quote, "[] ", .todo), (.heading3, "# ", .heading1), (.numbered, "``` ", .code),
    ])
    func worksInEveryTextBlock(from: BlockKind, prefix: String, to: BlockKind) {
        var document = doc(EditorBlock(kind: from, text: prefix + "Text"))
        let cursor = document.applyMarkdownShortcut(at: pos(0, prefix.utf16.count))
        #expect(document[0].kind == to)
        #expect(document[0].text == "Text")
        #expect(cursor == pos(0, 0))
    }

    @Test func listKeepsIndentWhenSwitchingListKind() {
        var document = doc(EditorBlock(kind: .bulleted, text: "1. A", indent: 1))
        _ = document.applyMarkdownShortcut(at: pos(0, 3))
        #expect(document[0].kind == .numbered)
        #expect(document[0].indent == 1)
    }

    @Test func notInCode() {
        var document = doc(EditorBlock(kind: .code, text: "- "))
        let cursor = document.applyMarkdownShortcut(at: pos(0, 2))
        #expect(cursor == nil)
        #expect(document[0].kind == .code)
    }
}

@Suite("Verschieben und Nummerierung")
struct MoveTests {
    private func letters() -> EditorDocument {
        doc(EditorBlock(text: "A"), EditorBlock(text: "B"), EditorBlock(text: "C"), EditorBlock(text: "D"))
    }

    @Test func movesDown() {
        var document = letters()
        let range = document.moveBlocks(IndexSet(integer: 0), to: 3)
        #expect(document.blocks.map(\.text) == ["B", "C", "A", "D"])
        #expect(range == 2..<3)
    }

    @Test func movesUp() {
        var document = letters()
        let range = document.moveBlocks(IndexSet(integer: 3), to: 1)
        #expect(document.blocks.map(\.text) == ["A", "D", "B", "C"])
        #expect(range == 1..<2)
    }

    @Test func movesSeveralToEnd() {
        var document = letters()
        let range = document.moveBlocks(IndexSet([0, 2]), to: 4)
        #expect(document.blocks.map(\.text) == ["B", "D", "A", "C"])
        #expect(range == 2..<4)
    }

    @Test func clampsIndentAtNewPlace() {
        var document = doc(EditorBlock(text: "A"), EditorBlock(kind: .bulleted, text: "B", indent: 2), EditorBlock(kind: .bulleted, text: "C", indent: 3))
        document.moveBlocks(IndexSet([1, 2]), to: 0)
        #expect(document.blocks.map(\.indent) == [0, 1, 0])
    }

    @Test func numberingRestartsAfterOtherBlocks() {
        let document = doc(
            EditorBlock(kind: .numbered, text: "a"), EditorBlock(kind: .numbered, text: "b"),
            EditorBlock(kind: .numbered, text: "b1", indent: 1),
            EditorBlock(kind: .numbered, text: "c"),
            EditorBlock(text: "Pause"),
            EditorBlock(kind: .numbered, text: "neu")
        )
        #expect([0, 1, 2, 3, 5].map(document.listOrdinal) == [1, 2, 1, 3, 1])
    }
}

@Suite("Markdown und Slash-Menü")
struct SerializerTests {
    @Test func serializesMixedBlocks() {
        let document = doc(
            EditorBlock(kind: .heading1, text: "Quill"),
            EditorBlock(text: "Notizen"),
            EditorBlock(kind: .numbered, text: "eins"),
            EditorBlock(kind: .numbered, text: "zwei"),
            EditorBlock(kind: .todo, text: "fertig", indent: 1, isChecked: true),
            EditorBlock(kind: .code, text: "let a = 1", codeLanguage: "swift"),
            EditorBlock(kind: .divider)
        )
        let markdown = MarkdownSerializer.markdown(for: document, blocks: 0..<document.count)
        #expect(markdown == """
        # Quill

        Notizen

        1. eins
        2. zwei
            - [x] fertig

        ```swift
        let a = 1
        ```

        ---
        """)
    }

    @Test func slashFilterIsAccentAndCaseInsensitive() {
        #expect(SlashCommand.matching("üb").map(\.kind) == [.heading1, .heading2, .heading3])
        #expect(SlashCommand.matching("h2").first?.kind == .heading2)
        #expect(SlashCommand.matching("todo").first?.kind == .todo)
        #expect(SlashCommand.matching("").count == SlashCommand.all.count)
    }

    @Test func slashMatchesAreGroupedBySection() {
        // „li“: Liste (Grundblöcke) und Linie (Weitere).
        #expect(SlashCommand.matching("li").map(\.kind) == [.bulleted, .numbered, .divider])
        for query in ["", "e", "o", "bild", "t"] {
            let groups = SlashCommand.matching(query).map(\.group)
            #expect(!groups.drop { $0 == .basic }.contains(.basic), "\(query)")
        }
    }
}

@Suite("Blöcke einfügen")
struct InsertBlocksTests {
    private let pasted = [EditorBlock(kind: .heading2, text: "X"), EditorBlock(kind: .todo, text: "Y")]

    @Test func replacesEmptyParagraph() {
        var document = doc(EditorBlock(text: "A"), EditorBlock())
        let cursor = document.insertBlocks(pasted, at: pos(1, 0))
        #expect(document.blocks.map(\.text) == ["A", "X", "Y"])
        #expect(cursor == pos(2, 1))
    }

    @Test func insertsBeforeAtBlockStart() {
        var document = doc(EditorBlock(text: "A"))
        document.insertBlocks(pasted, at: pos(0, 0))
        #expect(document.blocks.map(\.text) == ["X", "Y", "A"])
    }

    @Test func insertsAfterAtBlockEnd() {
        var document = doc(EditorBlock(text: "A"))
        let cursor = document.insertBlocks(pasted, at: pos(0, 1))
        #expect(document.blocks.map(\.text) == ["A", "X", "Y"])
        #expect(cursor == pos(2, 1))
    }

    @Test func splitsInTheMiddle() {
        var document = doc(EditorBlock(kind: .bulleted, text: "AB"))
        document.insertBlocks(pasted, at: pos(0, 1))
        #expect(document.blocks.map(\.text) == ["A", "X", "Y", "B"])
        #expect(document.blocks.map(\.kind) == [.bulleted, .heading2, .todo, .bulleted])
    }
}
