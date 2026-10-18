import Foundation
import Testing
import QuillModel
@testable import QuillEditor

@Suite("Zwischenablage: Format der Quill-Blöcke")
struct BlockClipboardTests {
    @Test func roundTripKeepsAllFields() throws {
        let blocks = [
            EditorBlock(kind: .todo, text: "Aufgabe", spans: [InlineSpan(0..<3, marks: [.bold])], indent: 2, isChecked: true),
            EditorBlock(kind: .code, text: "let a = 1", codeLanguage: "swift"),
        ]
        let data = try #require(BlockClipboard.encode(blocks))
        #expect(BlockClipboard.decode(data) == blocks)
    }

    @Test func writesVersion() throws {
        let data = try #require(BlockClipboard.encode([EditorBlock(text: "a")]))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 2)
    }

    @Test func version1IsNotReadAsBlocks() {
        let json = #"[{"id":"7A3B5B6E-6C2B-4C38-9E73-6C1C4D2E8F10","kind":"paragraph","text":"alt","indent":0,"isChecked":false}]"#
        #expect(BlockClipboard.decode(Data(json.utf8)) == nil)
    }

    @Test func unknownVersionIsNotReadAsBlocks() {
        let json = #"{"version":3,"blocks":[{"id":"7A3B5B6E-6C2B-4C38-9E73-6C1C4D2E8F10","kind":"paragraph","text":"neu","spans":[],"properties":{"indent":0,"isChecked":false}}]}"#
        #expect(BlockClipboard.decode(Data(json.utf8)) == nil)
    }

    @Test func unreadableDataIsNotReadAsBlocks() {
        #expect(BlockClipboard.decode(Data("kein JSON".utf8)) == nil)
        #expect(BlockClipboard.decode(Data(#"{"version":2,"blocks":[{"kind":"paragraph"}]}"#.utf8)) == nil)
    }
}
