import Foundation
import QuillEditor
import QuillModel

/// Gemeinsame Beispieldokumente der Editor- und Export-Tests (Nachfolger von
/// `SpikeSamples`, ADR-007). Eigenes Target, damit beide Testtargets sie nutzen.
public enum SampleDocuments {
    /// Alle Text-Blockarten und Inline-Formate, für den Snapshot-Test hell/dunkel.
    public static let welcome = EditorDocument(blocks: [
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

    /// Inline-Code direkt unter einem zweizeiligen Absatz (bekanntes Problem aus
    /// Phase 3) und ein Inline-Code, der über zwei Zeilen umbricht. Ohne `code`
    /// derselbe Text ohne Formatierung, zum Vergleich.
    public static func inlineCode(withCode: Bool = true) -> EditorDocument {
        let long = "Ein Absatz, der in einem schmalen Fenster über zwei Zeilen läuft, damit der Inline-Code darunter direkt an eine umbrochene Zeile grenzt."
        let wrapped = "Davor steht etwas Text und dann folgt ein ziemlich langer Abschnitt in Code, der am Zeilenende umbricht."
        let code = (wrapped as NSString).range(of: "ziemlich langer Abschnitt in Code")
        return EditorDocument(blocks: [
            EditorBlock(text: long),
            EditorBlock(text: "Code am Zeilenanfang, wie hinter „```“.", spans: withCode ? [InlineSpan(0..<4, marks: [.code])] : []),
            EditorBlock(text: wrapped, spans: withCode ? [InlineSpan(code.location..<NSMaxRange(code), marks: [.code])] : []),
            EditorBlock(text: "Ende"),
        ])
    }

    /// Inline-Code direkt vor einem weichen Umbruch (⇧↩), mit oder ohne den Umbruch
    /// in der Markierung.
    public static func inlineCodeBeforeSoftBreak(markingBreak: Bool) -> EditorDocument {
        EditorDocument(blocks: [
            EditorBlock(text: "code\nweiter", spans: [InlineSpan(0..<(markingBreak ? 5 : 4), marks: [.code])]),
        ])
    }

    /// Kurzes gemischtes Dokument für Zwischenablage und Verschieben.
    public static let mixed: [EditorBlock] = [
        EditorBlock(kind: .heading1, text: "Titel"),
        EditorBlock(kind: .todo, text: "Aufgabe", isChecked: true),
        EditorBlock(kind: .numbered, text: "eins"),
        EditorBlock(text: "Ende"),
    ]

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

    // MARK: - Export

    /// Feste IDs und Daten, damit die Golden Files des Exports stabil bleiben.
    public static let exportDate = Date(timeIntervalSince1970: 1_792_400_000) // 2026-10-19
    public static let exportImageID = UUID(uuidString: "3F2A9C1E-0000-4000-8000-000000000001")!
    public static let exportImage2ID = UUID(uuidString: "3F2A9C1E-0000-4000-8000-000000000002")!
    public static let exportMissingImageID = UUID(uuidString: "0BADF00D-0000-4000-8000-000000000003")!

    private static func exportID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!
    }

    /// Seitenbaum für den Export: alle Blockarten (`welcome`), Bilder auf zwei Ebenen,
    /// ein fehlendes Bild, gleiche Titel bis auf Groß-/Kleinschreibung, ein leerer
    /// Titel, Sonderzeichen, Umlaute und Emoji sowie ein Link mit Leerzeichen.
    public static func exportProject() -> PageExportSnapshot {
        func page(_ number: Int, _ title: String, blocks: [EditorBlock] = [], images: [UUID: String] = [:], children: [PageExportSnapshot] = []) -> PageExportSnapshot {
            PageExportSnapshot(
                id: exportID(number), title: title,
                createdAt: exportDate.addingTimeInterval(-86_400), updatedAt: exportDate,
                blocks: blocks.map(\.snapshot), imageTypes: images, children: children
            )
        }
        let image = EditorBlock(id: exportID(101), kind: .image, properties: BlockProperties(assetID: exportImageID))
        let nestedImage = EditorBlock(id: exportID(102), kind: .image, properties: BlockProperties(assetID: exportImage2ID))
        let missingImage = EditorBlock(id: exportID(103), kind: .image, properties: BlockProperties(assetID: exportMissingImageID))
        let link = EditorBlock(id: exportID(104), text: "Siehe Notiz mit Leerzeichen.", spans: [
            InlineSpan(6..<27, marks: [], link: "file:///Users/Shared/Meine Notiz.md"),
        ])
        return page(1, "Projekte", blocks: welcome.blocks + [image, link], images: [exportImageID: "public.png"], children: [
            page(2, "Quill", blocks: [EditorBlock(id: exportID(105), text: "Erste Unterseite"), nestedImage], images: [exportImage2ID: "public.png"], children: [
                page(3, "Notizen", blocks: [EditorBlock(id: exportID(106), kind: .todo, text: "Export testen")]),
            ]),
            page(4, "quill", blocks: [missingImage]),
            page(5, ""),
            page(6, ".Ärger: Ü/ß #1 [Entwurf]"),
            page(7, "🚀 Start 👩‍👩‍👧"),
        ])
    }
}
