import Foundation
import Testing
@testable import QuillEditor

// Rendern erzeugt Schriften (`NSFont`); das ist nur auf dem Main Thread zuverlässig,
// parallel auf anderen Threads kam sporadisch `nil` zurück.
@MainActor
@Suite("Abbildung Modell ↔ Textspeicher")
struct BlockRendererTests {
    private let blocks = [
        EditorBlock(kind: .heading1, text: "Titel"),
        EditorBlock(text: "Absatz"),
        EditorBlock(kind: .bulleted, text: "Punkt", indent: 2),
        EditorBlock(kind: .numbered, text: "eins"),
        EditorBlock(kind: .todo, text: "Aufgabe", isChecked: true),
        EditorBlock(kind: .quote, text: "Zitat"),
        EditorBlock(kind: .code, text: "a\nb", codeLanguage: "swift"),
        EditorBlock(kind: .divider),
        EditorBlock(),
    ]

    @Test func roundTripKeepsAllBlockFields() {
        let rendered = BlockRenderer.render(blocks[...], ordinals: [:])
        let (parsed, repaired) = BlockRenderer.parse(rendered)
        #expect(parsed == blocks)
        #expect(repaired.isEmpty)
    }

    @Test func everyParagraphEndsWithNewlineAndSoftBreaksStayInside() {
        let rendered = BlockRenderer.render(blocks[...], ordinals: [:]).string
        #expect(rendered.hasSuffix("\n"))
        #expect(rendered.components(separatedBy: "\n").count - 1 == blocks.count)
        #expect(rendered.contains("a\u{2028}b"))
        #expect(rendered.contains(StorageCharacter.attachment))
    }

    @Test func blockAttributesLieOnEveryCharacter() {
        let rendered = BlockRenderer.render(blocks[...], ordinals: [:])
        for index in 0..<rendered.length {
            #expect(rendered.attribute(.quillBlockID, at: index, effectiveRange: nil) != nil)
        }
    }

    @Test func missingAndDuplicateIDsAreRepaired() {
        let block = EditorBlock(text: "doppelt")
        let text = NSMutableAttributedString(attributedString: BlockRenderer.render([block, block][...], ordinals: [:]))
        text.append(NSAttributedString(string: "ohne\n"))
        let (parsed, repaired) = BlockRenderer.parse(text)
        #expect(parsed.map(\.text) == ["doppelt", "doppelt", "ohne"])
        #expect(parsed[0].id == block.id)
        #expect(Set(parsed.map(\.id)).count == 3)
        #expect(repaired.count == 2)
    }

    @Test func ordinalsRestartAfterOtherBlocksAndPerLevel() {
        let document = EditorDocument(blocks: [
            EditorBlock(kind: .numbered, text: "1"),
            EditorBlock(kind: .numbered, text: "1.1", indent: 1),
            EditorBlock(kind: .numbered, text: "1.2", indent: 1),
            EditorBlock(kind: .numbered, text: "2"),
            EditorBlock(text: "Unterbrechung"),
            EditorBlock(kind: .numbered, text: "neu 1"),
        ])
        let ordinals = BlockRenderer.ordinals(for: document)
        #expect(document.blocks.map { ordinals[$0.id] } == [1, 1, 2, 2, nil, 1])
    }
}
