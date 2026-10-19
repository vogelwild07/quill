import Foundation
import QuillModel

/// Ergebnis eines Exports für die Rückmeldung in der App.
public struct ExportResult: Equatable, Sendable {
    /// Der neu angelegte Export-Ordner.
    public var folder: URL
    public var pageCount: Int
    public var imageCount: Int
    /// Bilder, die als Kommentar statt als Link exportiert wurden, weil Asset oder
    /// Daten fehlten.
    public var missingImageCount: Int
}

/// Schreibt eine Seite (mit Unterseiten) als Markdown-Ordner (ADR-018).
///
/// Erst in einen Zwischenordner, dann ein Umbenennen in „<Seite> (Quill JJJJ-MM-TT)“.
/// So entsteht nie ein halber Export, und Vorhandenes wird nie überschrieben: Gibt
/// es den Namen schon, bekommt der neue Ordner einen Zähler („… 2“).
public enum ExportWriter {
    public static func export(
        _ root: PageExportSnapshot,
        strings: ExportStrings,
        into destination: URL,
        date: Date = .now,
        imageData: @Sendable (UUID) async throws -> Data?
    ) async throws -> ExportResult {
        let fileManager = FileManager()
        let staging = destination.appending(path: ".quill-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        // `export/` wird am Ende umbenannt, `images/` hält die Bilder bis dahin.
        let output = staging.appending(path: "export", directoryHint: .isDirectory)
        let images = staging.appending(path: "images", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: images, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: staging) }

        // Erst die Bilder: Fehlen Daten, steht im Markdown ein Kommentar statt eines
        // Links ins Leere.
        var missing: Set<UUID> = []
        for id in MarkdownExporter.imageIDs(in: root) {
            guard let data = try await imageData(id) else {
                missing.insert(id)
                continue
            }
            try data.write(to: images.appending(path: id.uuidString))
        }

        let plan = MarkdownExporter.plan(for: root, strings: strings, missingImages: missing)
        for file in plan.files {
            let url = output.appending(path: file.path, directoryHint: .notDirectory)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            switch file.content {
            case .markdown(let text):
                try Data(text.utf8).write(to: url)
            case .image(let id):
                try fileManager.moveItem(at: images.appending(path: id.uuidString), to: url)
            }
        }
        let folder = try moveIntoPlace(output, title: root.title, untitled: strings.untitled, in: destination, date: date, fileManager: fileManager)
        return ExportResult(
            folder: folder, pageCount: plan.pageCount,
            imageCount: plan.imageCount, missingImageCount: plan.missingImageCount
        )
    }

    /// Benennt den fertigen Ordner in den ersten freien Namen um.
    private static func moveIntoPlace(
        _ output: URL, title: String, untitled: String, in destination: URL, date: Date, fileManager: FileManager
    ) throws -> URL {
        var counter = 1
        while true {
            let name = ExportFileName.folderName(title: title, untitled: untitled, date: date, counter: counter)
            let target = destination.appending(path: name, directoryHint: .isDirectory)
            if !fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
                do {
                    try fileManager.moveItem(at: output, to: target)
                    return target
                } catch CocoaError.fileWriteFileExists {
                    // Zwischen Prüfen und Umbenennen angelegt: nächster Name.
                }
            }
            counter += 1
        }
    }
}

extension ExportFileName {
    /// „Projekte (Quill 2026-10-19)“, ab dem zweiten Versuch mit Zähler („… 2“).
    /// Das Datum ist lokal, wie der Nutzer es kennt.
    public static func folderName(title: String, untitled: String, date: Date, counter: Int, timeZone: TimeZone = .current) -> String {
        let day = date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day().dateSeparator(.dash))
        let suffix = " (Quill \(day))" + (counter == 1 ? "" : " \(counter)")
        return stem(base: base(for: title, untitled: untitled), suffix: suffix)
    }
}
