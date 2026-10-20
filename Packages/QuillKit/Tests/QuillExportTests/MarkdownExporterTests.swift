import Foundation
import QuillEditor
import QuillModel
import QuillTestFixtures
import Testing
@testable import QuillExport

@Suite struct MarkdownExporterTests {
    static let strings = ExportStrings(untitled: "Ohne Titel", subpages: "Unterseiten", missingImage: "Bild fehlt")

    private var plan: ExportPlan {
        MarkdownExporter.plan(for: SampleDocuments.exportProject(), strings: Self.strings)
    }

    /// Das Theme gilt nur für die Darstellung (ADR-024): Der Export ist in jedem gleich.
    @MainActor
    @Test(.renderingLock) func exportIsTheSameInEveryTheme() {
        func files() -> [String] {
            MarkdownExporter.plan(for: SampleDocuments.exportProject(), strings: Self.strings).files.map { file in
                switch file.content {
                case .markdown(let text): file.path + "\n" + text
                case .image(let id): file.path + " ← " + id.uuidString
                }
            }
        }
        EditorThemeSettings.shared.configure(defaults: nil, initial: .standard)
        defer { EditorThemeSettings.shared.configure(defaults: nil, initial: .standard) }
        let standard = files()
        for id in EditorTheme.ID.allCases {
            EditorThemeSettings.shared.select(id)
            #expect(files() == standard, "\(id)")
        }
    }

    // MARK: - Golden Files

    /// Vergleicht den Export von `SampleDocuments.exportProject()` mit
    /// `Golden/ExportProject/`. Neu schreiben: `QUILL_UPDATE_GOLDEN=1 swift test --filter MarkdownExporterTests`.
    @Test func matchesGoldenFiles() throws {
        let golden = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Golden/ExportProject")
        let listing = plan.files.map { file in
            switch file.content {
            case .markdown: file.path
            case .image(let id): file.path + " ← " + id.uuidString
            }
        }.joined(separator: "\n") + "\n"

        if ProcessInfo.processInfo.environment["QUILL_UPDATE_GOLDEN"] == "1" {
            try? FileManager.default.removeItem(at: golden)
            try write(listing, to: golden.appending(path: "files.txt"))
            for file in plan.files {
                if case .markdown(let text) = file.content {
                    try write(text, to: golden.appending(path: file.path))
                }
            }
            Issue.record("Golden Files neu geschrieben, Test ohne QUILL_UPDATE_GOLDEN wiederholen.")
            return
        }

        #expect(listing == (try String(contentsOf: golden.appending(path: "files.txt"), encoding: .utf8)))
        for file in plan.files {
            guard case .markdown(let text) = file.content else { continue }
            let expected = try String(contentsOf: golden.appending(path: file.path), encoding: .utf8)
            #expect(text == expected, "Abweichung in \(file.path)")
        }
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    // MARK: - Links

    /// Jeder relative Link (Bilder und Unterseiten) zeigt auf eine Datei des Exports.
    @Test func everyRelativeLinkPointsToAnExportedFile() throws {
        let paths = Set(plan.files.map(\.path))
        var checked = 0
        for file in plan.files {
            guard case .markdown(let text) = file.content else { continue }
            let directory = file.path.split(separator: "/").dropLast().map(String.init)
            for target in Self.linkTargets(in: text) where !target.contains("://") {
                let resolved = Self.resolve(target, from: directory)
                #expect(paths.contains(resolved), "\(file.path): \(target) → \(resolved) fehlt")
                checked += 1
            }
        }
        // Zwei Bilder und fünf Unterseiten-Links (Projekte: 5, Quill: 1) = 8.
        #expect(checked == 8)
    }

    @Test func imagesLiveInRootAssetsFolder() {
        let images = plan.files.filter { if case .image = $0.content { true } else { false } }
        #expect(images.map(\.path) == ["assets/3F2A9C1E.png", "assets/3F2A9C1E 2.png"])
        #expect(plan.imageCount == 2)
        #expect(plan.pageCount == 7)
    }

    @Test func missingImageBecomesCommentNotLink() throws {
        let page = try #require(markdown(at: "Projekte/quill 2.md"))
        #expect(page.contains("<!-- Bild fehlt -->"))
        #expect(!page.contains("!["))
        #expect(plan.missingImageCount == 1)
    }

    /// Bilder, deren Daten beim Laden fehlten, werden wie fehlende Assets behandelt.
    @Test func imagesWithoutDataBecomeComments() throws {
        let root = SampleDocuments.exportProject()
        #expect(MarkdownExporter.imageIDs(in: root) == [SampleDocuments.exportImageID, SampleDocuments.exportImage2ID])
        let partial = MarkdownExporter.plan(for: root, strings: Self.strings, missingImages: [SampleDocuments.exportImageID])
        #expect(partial.imageCount == 1)
        #expect(partial.missingImageCount == 2)
        guard case .markdown(let text) = partial.files[0].content else {
            Issue.record("Keine Seite")
            return
        }
        #expect(!text.contains("![]("))
    }

    @Test func linksWithSpacesUseAngleBrackets() throws {
        let root = try #require(markdown(at: "Projekte.md"))
        #expect(root.contains("[Notiz mit Leerzeichen](<file:///Users/Shared/Meine Notiz.md>)"))
        #expect(root.contains("- [Ohne Titel](<Projekte/Ohne Titel.md>)"))
        #expect(root.contains("- [Quill](Projekte/Quill.md)"))
        let nested = try #require(markdown(at: "Projekte/Quill.md"))
        #expect(nested.contains("![](<../assets/3F2A9C1E 2.png>)"))
    }

    @Test func subpagesOnlyWhenIncluded() {
        var root = SampleDocuments.exportProject()
        root.children = []
        let single = MarkdownExporter.plan(for: root, strings: Self.strings)
        #expect(single.files.map(\.path) == ["Projekte.md", "assets/3F2A9C1E.png"])
        guard case .markdown(let text) = single.files[0].content else { return }
        #expect(!text.contains("Unterseiten"))
    }

    /// Eine Seite „assets“ mit Unterseiten bekommt einen anderen Ordner als die Bilder.
    @Test func pageNamedAssetsDoesNotClashWithImages() {
        let root = PageExportSnapshot(title: "Assets", children: [PageExportSnapshot(title: "Kind")])
        let paths = MarkdownExporter.plan(for: root, strings: Self.strings).files.map(\.path)
        #expect(paths == ["Assets 2.md", "Assets 2/Kind.md"])
    }

    @Test func yamlStringEscapes() {
        #expect(MarkdownExporter.yamlString(#"Sag "Hallo" \ Welt"#) == #""Sag \"Hallo\" \\ Welt""#)
        #expect(MarkdownExporter.yamlString("a\u{2028}b\tc") == #""a\u2028b\u0009c""#)
        #expect(MarkdownExporter.yamlString("Ärger: 🚀 #1") == #""Ärger: 🚀 #1""#)
    }

    // MARK: - Hilfen

    private func markdown(at path: String) -> String? {
        plan.files.first { $0.path == path }.flatMap { file in
            if case .markdown(let text) = file.content { text } else { nil }
        }
    }

    /// Ziele von `[…](Ziel)` und `![…](Ziel)`, mit und ohne spitze Klammern.
    static func linkTargets(in text: String) -> [String] {
        let pattern = /\]\((?:<((?:\\.|[^>\\])*)>|([^)\s]*))\)/
        return text.matches(of: pattern).map { match in
            if let bracketed = match.1 {
                String(bracketed).replacing(/\\(.)/) { String($0.1) }
            } else {
                String(match.2 ?? "")
            }
        }
    }

    static func resolve(_ target: String, from directory: [String]) -> String {
        var parts = directory
        for part in target.split(separator: "/") {
            if part == ".." { _ = parts.popLast() } else if part != "." { parts.append(String(part)) }
        }
        return parts.joined(separator: "/")
    }
}
