import Foundation
import QuillModel
import Testing
@testable import QuillEditor

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
