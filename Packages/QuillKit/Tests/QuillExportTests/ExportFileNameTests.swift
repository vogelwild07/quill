import Foundation
import Testing
@testable import QuillExport

@Suite struct ExportFileNameTests {
    private func base(_ title: String) -> String {
        ExportFileName.base(for: title, untitled: "Ohne Titel")
    }

    @Test func replacesCharactersThatBreakPathsOrLinks() {
        #expect(base(#"a/b\c:d*e?f"g<h>i|j#k^l[m]n%o"#) == "a-b-c-d-e-f-g-h-i-j-k-l-m-n-o")
    }

    @Test func replacesLeadingDots() {
        #expect(base(".versteckt") == "-versteckt")
        #expect(base("..zwei") == "--zwei")
        #expect(base("  .nach Leerzeichen") == "-nach Leerzeichen")
        #expect(base("Ende.") == "Ende.")
    }

    @Test func emptyTitleBecomesUntitled() {
        #expect(base("") == "Ohne Titel")
        #expect(base(" \t\u{2028} ") == "Ohne Titel")
    }

    @Test func collapsesWhitespaceAndInvisibleCharacters() {
        #expect(base("Zeile\u{2028}zwei\tdrei  vier\u{200B}fünf") == "Zeile zwei drei vier fünf")
    }

    @Test func keepsUmlautsAndEmoji() {
        let title = "Äpfel & Öl 🍎 👩‍👩‍👧 🇩🇪"
        #expect(base(title) == title)
    }

    /// APFS: höchstens 255 Bytes UTF-8; gekürzt wird nur an Zeichengrenzen und nur
    /// die Basis, Zähler und Endung bleiben.
    @Test(arguments: [
        String(repeating: "👩‍👩‍👧", count: 40), // 18 Bytes pro Zeichen
        String(repeating: "ä", count: 200), // 2 Bytes
        String(repeating: "a", count: 300),
        String(repeating: "o\u{0308}", count: 130), // zerlegtes „ö“, 3 Bytes
    ])
    func limitsNamesTo255Bytes(_ title: String) {
        let stem = ExportFileName.base(for: title, untitled: "x")
        for (suffix, ext) in [("", "md"), (" 2", "md"), (" 12", ""), ("", "png")] {
            let name = ExportFileName.name(base: stem, suffix: suffix, extension: ext)
            #expect(name.utf8.count <= ExportFileName.maxBytes, "\(name.utf8.count) Bytes")
            #expect(name.hasSuffix(suffix + (ext.isEmpty ? "" : "." + ext)))
            let kept = name.dropLast((suffix + (ext.isEmpty ? "" : "." + ext)).count)
            #expect(title.hasPrefix(kept), "Zeichen zerbrochen")
            #expect(kept.count > 0)
        }
    }

    @Test func collisionKeyIgnoresCaseAndNormalization() {
        #expect(ExportFileName.collisionKey("Quill.md") == ExportFileName.collisionKey("quill.MD"))
        // „Ä“ zusammengesetzt (U+00C4) und zerlegt (A + U+0308).
        #expect(ExportFileName.collisionKey("\u{00C4}rger") == ExportFileName.collisionKey("A\u{0308}rger"))
        #expect(ExportFileName.collisionKey("Ärger") == ExportFileName.collisionKey("ärger"))
        #expect(ExportFileName.collisionKey("Quill") != ExportFileName.collisionKey("Quil"))
    }

    @Test func registryCountsUpCaseInsensitively() {
        var names = ExportNameRegistry()
        #expect(names.claim(base: "Quill", extensions: ["md"]) == "Quill")
        #expect(names.claim(base: "quill", extensions: ["md"]) == "quill 2")
        #expect(names.claim(base: "QUILL", extensions: ["md"]) == "QUILL 3")
        #expect(names.claim(base: "A\u{0308}rger", extensions: ["md"]) == "A\u{0308}rger")
        #expect(names.claim(base: "\u{00C4}rger", extensions: ["md"]) == "\u{00C4}rger 2")
    }

    /// Eine Seite mit Unterseiten belegt „Titel.md“ und den Ordner „Titel“; eine
    /// Seite „Titel.md“ hätte sonst denselben Namen wie die Datei.
    @Test func registryReservesFileAndFolderTogether() {
        var names = ExportNameRegistry(reserved: ["assets"])
        #expect(names.claim(base: "Titel", extensions: ["md", ""]) == "Titel")
        #expect(names.claim(base: "titel.md", extensions: [""]) == "titel.md 2")
        #expect(names.claim(base: "Assets", extensions: ["md", ""]) == "Assets 2")
        #expect(names.claim(base: "Assets", extensions: ["md"]) == "Assets")
    }

    @Test func folderNameHasDateAndCounter() {
        let date = Date(timeIntervalSince1970: 1_792_400_000)
        let utc = TimeZone(identifier: "UTC")!
        #expect(ExportFileName.folderName(title: "Projekte", untitled: "Ohne Titel", date: date, counter: 1, timeZone: utc) == "Projekte (Quill 2026-10-19)")
        #expect(ExportFileName.folderName(title: "Projekte", untitled: "Ohne Titel", date: date, counter: 2, timeZone: utc) == "Projekte (Quill 2026-10-19) 2")
        #expect(ExportFileName.folderName(title: "", untitled: "Ohne Titel", date: date, counter: 1, timeZone: utc) == "Ohne Titel (Quill 2026-10-19)")
        let long = ExportFileName.folderName(title: String(repeating: "ü", count: 200), untitled: "", date: date, counter: 3, timeZone: utc)
        #expect(long.utf8.count <= ExportFileName.maxBytes)
        #expect(long.hasSuffix(" (Quill 2026-10-19) 3"))
    }
}
