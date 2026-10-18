import Foundation
import QuillEditor

/// Beispielinhalte für den Spike (eigene Texte).
enum SpikeSamples {
    static let welcome = EditorDocument(blocks: [
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
}
