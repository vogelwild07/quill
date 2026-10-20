import Foundation
@testable import QuillEditor
@testable import QuillEditorCore
import QuillModel
import Testing

/// Eigene Datei: `QuillModel` und `QuillEditor` haben beide einen Typ `BlockKind`.
@Suite("Inline-Formatierung: RichText")
struct RichTextTests {
    @Test func richTextRoundTrip() throws {
        var content = InlineText("Hallo schöne Welt")
        content.setMark(.bold, true, in: 0..<5)
        content.setLink("https://quill.app", in: 13..<17)
        let rich = try #require(content.richText)
        #expect(rich.runs.map(\.text) == ["Hallo", " schöne ", "Welt"])
        let decoded = try #require(RichText.decode(try rich.encoded()))
        #expect(InlineText(text: content.text, richText: decoded) == content)
    }

    @Test func plainTextHasNoRichText() {
        #expect(InlineText("nur Text").richText == nil)
    }

    @Test func mismatchedRichTextFallsBackToPlainText() {
        let rich = RichText(runs: [.init(text: "alt", marks: ["bold"])])
        #expect(InlineText(text: "neu", richText: rich) == InlineText("neu"))
    }

    @Test func unknownMarksSurvive() throws {
        let rich = RichText(runs: [.init(text: "x", marks: ["highlight"])])
        let content = InlineText(text: "x", richText: rich)
        #expect(content.spans.first?.style.marks == [InlineMark(rawValue: "highlight")])
        #expect(content.richText == rich)
    }

    @Test func encodingIsStable() throws {
        let rich = RichText(runs: [.init(text: "a/b", marks: ["italic", "bold"], link: "https://x.y/z")])
        let json = String(decoding: try rich.encoded(), as: UTF8.self)
        #expect(json == #"{"runs":[{"link":"https://x.y/z","marks":["bold","italic"],"text":"a/b"}],"version":1}"#)
    }
}

@Suite("Markdown: Link-Ziele")
struct MarkdownLinkDestinationTests {
    @Test func plainTargetsStayAsTheyAre() {
        #expect(MarkdownSerializer.linkDestination("https://apple.com/a?b=c#d") == "https://apple.com/a?b=c#d")
        #expect(MarkdownSerializer.linkDestination("Quill/Notizen.md") == "Quill/Notizen.md")
        #expect(MarkdownSerializer.linkDestination("../assets/3F2A9C1E.png") == "../assets/3F2A9C1E.png")
    }

    @Test func spacesParenthesesAndBracketsUseAngleBrackets() {
        #expect(MarkdownSerializer.linkDestination("Ohne Titel.md") == "<Ohne Titel.md>")
        #expect(MarkdownSerializer.linkDestination("Wiki_(Begriff)") == "<Wiki_(Begriff)>")
        #expect(MarkdownSerializer.linkDestination("a<b>c") == #"<a\<b\>c>"#)
        #expect(MarkdownSerializer.linkDestination("Zeile\nzwei") == "<Zeile zwei>")
    }

    @Test func inlineLinkWithSpaceIsBracketed() {
        let text = InlineText("Siehe Notiz", spans: [InlineSpan(6..<11, marks: [], link: "Meine Notiz.md")])
        #expect(MarkdownSerializer.inlineMarkdown(text) == "Siehe [Notiz](<Meine Notiz.md>)")
    }

    @Test func linkTextEscapesBrackets() {
        #expect(MarkdownSerializer.linkText(#"[Entwurf] a\b"#) == #"\[Entwurf\] a\\b"#)
    }
}
