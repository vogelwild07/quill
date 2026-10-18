#if os(macOS)
import Foundation
import QuillEditor

/// Beispielinhalte für den Spike (eigene Texte).
public enum SpikeSamples {
    public static let welcome = EditorDocument(blocks: [
        EditorBlock(kind: .heading1, text: "Quill-Editor-Spike"),
        EditorBlock(text: "Tippe „/“ für das Blockmenü oder nutze Markdown-Kürzel wie „# “, „- “, „1. “, „[] “, „> “, „``` “ und „---“."),
        EditorBlock(kind: .heading2, text: "Ziele"),
        EditorBlock(kind: .todo, text: "Block-Editor-Spike abschließen"),
        EditorBlock(kind: .todo, text: "Datenmodell entwerfen", isChecked: true),
        EditorBlock(kind: .bulleted, text: "Schnell"),
        EditorBlock(kind: .bulleted, text: "Start unter einer Sekunde", indent: 1),
        EditorBlock(kind: .bulleted, text: "Nativ"),
        EditorBlock(kind: .numbered, text: "Erst messen"),
        EditorBlock(kind: .numbered, text: "Dann entscheiden"),
        EditorBlock(kind: .quote, text: "Gute Werkzeuge treten zurück und lassen den Text sprechen."),
        EditorBlock(kind: .code, text: "let quill = \"local-first\"\nprint(quill)", codeLanguage: "swift"),
        EditorBlock(kind: .divider),
        EditorBlock(text: "Ziehe Blöcke am Griff links, markiere über mehrere Blöcke und kopiere mit ⌘C."),
    ])

    /// Großes Dokument mit gemischten Blockarten für Messungen.
    public static func large(blockCount: Int) -> EditorDocument {
        let sentence = "Quill speichert lokal, startet schnell und hält den Text im Mittelpunkt. "
        var blocks: [EditorBlock] = []
        blocks.reserveCapacity(blockCount)
        for index in 0..<blockCount {
            switch index % 20 {
            case 0: blocks.append(EditorBlock(kind: .heading2, text: "Abschnitt \(index / 20 + 1)"))
            case 1...3: blocks.append(EditorBlock(kind: .bulleted, text: "Punkt \(index)", indent: index % 2))
            case 4...6: blocks.append(EditorBlock(kind: .numbered, text: "Schritt \(index)"))
            case 7, 8: blocks.append(EditorBlock(kind: .todo, text: "Aufgabe \(index)", isChecked: index % 2 == 0))
            case 9: blocks.append(EditorBlock(kind: .quote, text: sentence))
            case 10: blocks.append(EditorBlock(kind: .code, text: "func f\(index)() {\n    return\n}", codeLanguage: "swift"))
            default: blocks.append(EditorBlock(text: String(repeating: sentence, count: 1 + index % 3)))
            }
        }
        return EditorDocument(blocks: blocks)
    }
}
#endif
