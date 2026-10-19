import Foundation
import QuillModel
import QuillTestFixtures
import Testing
@testable import QuillExport

/// Schreiben in einen temporären Ordner pro Test.
@Suite struct ExportWriterTests {
    private let destination: URL
    private let plan = MarkdownExporter.plan(for: SampleDocuments.exportProject(), strings: MarkdownExporterTests.strings)
    private static let quillPage = "Projekte/Quill.md"
    private let utc = TimeZone(identifier: "UTC")!

    init() throws {
        destination = FileManager.default.temporaryDirectory.appending(path: "QuillExportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    private func export(imageData: @escaping @Sendable (UUID) async throws -> Data? = { Data($0.uuidString.utf8) }) async throws -> ExportResult {
        try await ExportWriter.export(
            SampleDocuments.exportProject(), strings: MarkdownExporterTests.strings, into: destination,
            date: SampleDocuments.exportDate, imageData: imageData
        )
    }

    private func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: destination.path(percentEncoded: false)).sorted()
    }

    private var folderName: String {
        ExportFileName.folderName(title: "Projekte", untitled: "Ohne Titel", date: SampleDocuments.exportDate, counter: 1)
    }

    @Test func writesAllFilesIntoNewFolder() async throws {
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = try await export()

        #expect(result.folder.lastPathComponent == folderName)
        #expect(result.pageCount == 7)
        #expect(result.imageCount == 2)
        // Das Bild ohne Asset auf „quill“.
        #expect(result.missingImageCount == 1)
        #expect(try contents() == [folderName], "Kein Zwischenordner übrig")
        for file in plan.files {
            let data = try Data(contentsOf: result.folder.appending(path: file.path))
            switch file.content {
            case .markdown(let text): #expect(data == Data(text.utf8), "\(file.path)")
            case .image(let id): #expect(data == Data(id.uuidString.utf8), "\(file.path)")
            }
        }
    }

    /// Nie überschreiben: Ein vorhandener Ordner (auch in anderer Schreibweise)
    /// führt zu „… 2“, „… 3“.
    @Test func neverOverwritesExistingFolder() async throws {
        defer { try? FileManager.default.removeItem(at: destination) }
        let existing = destination.appending(path: folderName.lowercased())
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        try Data("alt".utf8).write(to: existing.appending(path: "Projekte.md"))

        let second = try await export()
        let third = try await export()

        #expect(second.folder.lastPathComponent == folderName + " 2")
        #expect(third.folder.lastPathComponent == folderName + " 3")
        #expect(try Data(contentsOf: existing.appending(path: "Projekte.md")) == Data("alt".utf8))
        #expect(try contents().count == 3)
    }

    /// Scheitert ein Schritt, bleibt im Ziel nichts liegen.
    @Test func failureLeavesNothingBehind() async throws {
        defer { try? FileManager.default.removeItem(at: destination) }
        struct Broken: Error {}
        await #expect(throws: Broken.self) {
            try await export { _ in throw Broken() }
        }
        #expect(try contents().isEmpty)
    }

    /// Fehlen die Daten eines Bildes, steht im Markdown ein Kommentar statt eines
    /// Links ins Leere, und die Meldung zählt es mit.
    @Test func missingImageDataBecomesCommentNotDeadLink() async throws {
        defer { try? FileManager.default.removeItem(at: destination) }
        let missing = SampleDocuments.exportImage2ID
        let result = try await export { $0 == missing ? nil : Data() }
        #expect(result.imageCount == 1)
        #expect(result.missingImageCount == 2)

        let page = try String(contentsOf: result.folder.appending(path: Self.quillPage), encoding: .utf8)
        #expect(page.contains("<!-- Bild fehlt -->"))
        #expect(!page.contains("!["))
        let assets = try FileManager.default.contentsOfDirectory(atPath: result.folder.appending(path: "assets").path(percentEncoded: false))
        #expect(assets == ["3F2A9C1E.png"])
    }
}
