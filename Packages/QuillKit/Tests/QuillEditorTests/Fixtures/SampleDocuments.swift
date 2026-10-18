import Foundation
@testable import QuillEditor

/// Gemeinsame Beispieldokumente der Editor-Tests (Nachfolger von `SpikeSamples`, ADR-007).
enum SampleDocuments {
    /// Alle Text-Blockarten und Inline-Formate, für den Snapshot-Test hell/dunkel.
    static let welcome = EditorDocument(blocks: [
        EditorBlock(kind: .heading1, text: "Willkommen in Quill"),
        EditorBlock(text: "Tippe „/“ für das Blockmenü oder nutze Markdown-Kürzel wie „# “, „- “, „1. “, „[] “, „> “, „``` “ und „---“."),
        EditorBlock(text: "Fett, kursiv, Code, durchgestrichen und ein Link.", spans: [
            InlineSpan(0..<4, marks: [.bold]), InlineSpan(6..<12, marks: [.italic]), InlineSpan(14..<18, marks: [.code]),
            InlineSpan(20..<35, marks: [.strikethrough]), InlineSpan(44..<48, marks: [], link: "https://apple.com"),
        ]),
        EditorBlock(kind: .heading2, text: "Ziele"),
        EditorBlock(kind: .todo, text: "Editor alltagstauglich machen"),
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

    /// Kurzes gemischtes Dokument für Zwischenablage und Verschieben.
    static let mixed: [EditorBlock] = [
        EditorBlock(kind: .heading1, text: "Titel"),
        EditorBlock(kind: .todo, text: "Aufgabe", isChecked: true),
        EditorBlock(kind: .numbered, text: "eins"),
        EditorBlock(text: "Ende"),
    ]

    /// Großes Dokument mit gemischten Blockarten für Messungen.
    static func large(blockCount: Int) -> EditorDocument {
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
