import Foundation
import QuillModel
import Testing
@testable import QuillEditor

private let bold: Set<InlineMark> = [.bold]

@Suite("Inline-Formatierung: InlineText")
struct InlineTextTests {
    @Test func normalizeMergesTouchingEqualSpansAndDropsPlainOnes() {
        let text = InlineText("abcdef", spans: [
            InlineSpan(2..<4, marks: bold),
            InlineSpan(0..<2, marks: bold),
            InlineSpan(4..<5, marks: []),
            InlineSpan(5..<9, marks: [.italic]),
        ])
        #expect(text.spans == [InlineSpan(0..<4, marks: bold), InlineSpan(5..<6, marks: [.italic])])
    }

    @Test func overlappingSpansAreSegmented() {
        let text = InlineText("abcdef", spans: [InlineSpan(0..<4, marks: bold), InlineSpan(2..<6, marks: [.italic])])
        #expect(text.spans == [
            InlineSpan(0..<2, marks: bold),
            InlineSpan(2..<4, marks: [.bold, .italic]),
            InlineSpan(4..<6, marks: [.italic]),
        ])
    }

    @Test func splitAndJoinRoundTrip() {
        let text = InlineText("Hallo Welt", spans: [InlineSpan(3..<8, marks: bold)])
        let (head, tail) = text.split(at: 5)
        #expect(head == InlineText("Hallo", spans: [InlineSpan(3..<5, marks: bold)]))
        #expect(tail == InlineText(" Welt", spans: [InlineSpan(0..<3, marks: bold)]))
        #expect(head + tail == text)
    }

    @Test func splitCountsUTF16() {
        let text = InlineText("😀ab", spans: [InlineSpan(2..<4, marks: bold)])
        let (head, tail) = text.split(at: 2)
        #expect(head.text == "😀")
        #expect(head.spans.isEmpty)
        #expect(tail.spans == [InlineSpan(0..<2, marks: bold)])
    }

    @Test func setMarkAddsAndRemovesInsideRange() {
        var text = InlineText("abcdef")
        text.setMark(.bold, true, in: 1..<5)
        #expect(text.spans == [InlineSpan(1..<5, marks: bold)])
        text.setMark(.italic, true, in: 3..<6)
        text.setMark(.bold, false, in: 2..<4)
        #expect(text.spans == [
            InlineSpan(1..<2, marks: bold),
            InlineSpan(3..<4, marks: [.italic]),
            InlineSpan(4..<5, marks: [.bold, .italic]),
            InlineSpan(5..<6, marks: [.italic]),
        ])
    }

    @Test func hasMarkRequiresFullCoverage() {
        let text = InlineText("abcdef", spans: [InlineSpan(0..<2, marks: bold), InlineSpan(2..<4, marks: [.bold, .italic])])
        #expect(text.hasMark(.bold, in: 0..<4))
        #expect(!text.hasMark(.bold, in: 0..<5))
        #expect(!text.hasMark(.italic, in: 1..<3))
    }

    @Test func linkRangeSpansDifferentMarks() {
        var text = InlineText("siehe Quill hier")
        text.setLink("https://quill.app", in: 6..<11)
        text.setMark(.bold, true, in: 6..<8)
        let found = text.linkRange(at: 9)
        #expect(found?.range == 6..<11)
        #expect(found?.link == "https://quill.app")
        #expect(text.linkRange(at: 2) == nil)
    }

    @Test func codeBlocksNeverCarryMarks() {
        var block = EditorBlock(kind: .code, text: "let a", spans: [InlineSpan(0..<3, marks: bold)])
        #expect(block.spans.isEmpty)
        block.content = InlineText("let b", spans: [InlineSpan(0..<3, marks: bold)])
        #expect(block.spans.isEmpty)
    }
}

@Suite("Inline-Formatierung: Dokument-Operationen")
struct InlineDocumentTests {
    private func formatted(_ kind: BlockKind = .paragraph) -> EditorBlock {
        EditorBlock(kind: kind, text: "Hallo Welt", spans: [InlineSpan(0..<5, marks: bold), InlineSpan(6..<10, marks: [.italic])])
    }

    @Test func enterSplitsFormatting() {
        var document = EditorDocument(blocks: [formatted()])
        document.splitBlock(at: BlockPosition(block: 0, offset: 3))
        #expect(document[0].spans == [InlineSpan(0..<3, marks: bold)])
        #expect(document[1].text == "lo Welt")
        #expect(document[1].spans == [InlineSpan(0..<2, marks: bold), InlineSpan(3..<7, marks: [.italic])])
    }

    @Test func backspaceJoinsFormatting() {
        var document = EditorDocument(blocks: [EditorBlock(text: "ab", spans: [InlineSpan(0..<2, marks: bold)]), formatted()])
        #expect(document.deleteBackwardAtStart(of: 1) == BlockPosition(block: 0, offset: 2))
        #expect(document[0].text == "abHallo Welt")
        #expect(document[0].spans == [InlineSpan(0..<7, marks: bold), InlineSpan(8..<12, marks: [.italic])])
    }

    @Test func joiningIntoCodeDropsMarks() {
        var document = EditorDocument(blocks: [EditorBlock(kind: .code, text: "x"), formatted()])
        #expect(document.deleteBackwardAtStart(of: 1) == BlockPosition(block: 0, offset: 1))
        #expect(document.count == 1)
        #expect(document[0].text == "xHallo Welt")
        #expect(document[0].spans.isEmpty)
    }

    @Test func replaceAcrossBlocksKeepsOuterFormatting() {
        var document = EditorDocument(blocks: [formatted(), formatted()])
        document.replace(from: BlockPosition(block: 0, offset: 2), to: BlockPosition(block: 1, offset: 8), with: "X")
        #expect(document[0].text == "HaXlt")
        #expect(document[0].spans == [InlineSpan(0..<2, marks: bold), InlineSpan(3..<5, marks: [.italic])])
    }

    @Test func markdownShortcutKeepsFormattingOfRest() {
        var document = EditorDocument(blocks: [EditorBlock(text: "# Titel", spans: [InlineSpan(2..<7, marks: bold)])])
        let cursor = document.applyMarkdownShortcut(at: BlockPosition(block: 0, offset: 2))
        #expect(cursor == BlockPosition(block: 0, offset: 0))
        #expect(document[0].kind == .heading1)
        #expect(document[0].spans == [InlineSpan(0..<5, marks: bold)])
    }

    @Test func turningIntoCodeClearsMarks() {
        var document = EditorDocument(blocks: [formatted()])
        document.setKind(.code, at: 0)
        #expect(document[0].spans.isEmpty)
    }

    @Test func toggleAcrossBlocksSkipsCode() {
        var document = EditorDocument(blocks: [
            EditorBlock(text: "eins"),
            EditorBlock(kind: .code, text: "zwei"),
            EditorBlock(text: "drei", spans: [InlineSpan(0..<4, marks: bold)]),
        ])
        let start = BlockPosition(block: 0, offset: 1)
        let end = BlockPosition(block: 2, offset: 2)
        #expect(!document.hasMark(.bold, from: start, to: end))
        let toggled = document.toggleMark(.bold, from: start, to: end)
        #expect(toggled)
        #expect(document[0].spans == [InlineSpan(1..<4, marks: bold)])
        #expect(document[1].spans.isEmpty)
        #expect(document.hasMark(.bold, from: start, to: end))
        document.toggleMark(.bold, from: start, to: end)
        #expect(document[0].spans.isEmpty)
        #expect(document[2].spans == [InlineSpan(2..<4, marks: bold)])
    }

    @Test func insertInlineKeepsFormattingOfBothSides() {
        var document = EditorDocument(blocks: [formatted()])
        let inserted = InlineText("NEU", spans: [InlineSpan(0..<3, marks: [.code])])
        let cursor = document.insertInline(inserted, from: BlockPosition(block: 0, offset: 5), to: BlockPosition(block: 0, offset: 6))
        #expect(document[0].text == "HalloNEUWelt")
        #expect(cursor == BlockPosition(block: 0, offset: 8))
        #expect(document[0].spans == [
            InlineSpan(0..<5, marks: bold), InlineSpan(5..<8, marks: [.code]), InlineSpan(8..<12, marks: [.italic]),
        ])
    }
}

@Suite("Inline-Formatierung: Markdown")
struct InlineSerializationTests {
    @Test func markdownWrapsMarksAndKeepsSpacesOutside() {
        let content = InlineText("fett und kursiv ", spans: [
            InlineSpan(0..<5, marks: bold),
            InlineSpan(9..<16, marks: [.italic]),
        ])
        #expect(MarkdownSerializer.inlineMarkdown(content) == "**fett** und _kursiv_ ")
    }

    @Test func markdownForLinkCodeAndStrikethrough() {
        var content = InlineText("Quill ist `neu` alt")
        content.setLink("https://quill.app", in: 0..<5)
        content.setMark(.bold, true, in: 0..<5)
        content.setMark(.code, true, in: 10..<15)
        content.setMark(.strikethrough, true, in: 16..<19)
        #expect(MarkdownSerializer.inlineMarkdown(content) == "[**Quill**](https://quill.app) ist `` `neu` `` ~~alt~~")
    }

    @Test func blockMarkdownUsesInlineMarks() {
        let document = EditorDocument(blocks: [
            EditorBlock(kind: .heading2, text: "Ziel", spans: [InlineSpan(0..<4, marks: [.italic])]),
            EditorBlock(kind: .todo, text: "fertig", spans: [InlineSpan(0..<6, marks: bold)], isChecked: true),
        ])
        #expect(MarkdownSerializer.markdown(for: document, blocks: 0..<2) == "## _Ziel_\n\n- [x] **fertig**")
    }
}
