import Foundation

/// Ergebnis eines Exports für die Rückmeldung in der App.
public struct ExportResult: Equatable, Sendable {
    /// Der neu angelegte Export-Ordner.
    public var folder: URL
    public var pageCount: Int
    public var imageCount: Int
    /// Bilder, deren Daten beim Schreiben fehlten (sollte nicht vorkommen).
    public var missingImageCount: Int
}

/// Schreibt einen `ExportPlan` auf die Platte (ADR-018).
///
/// Erst in einen versteckten Zwischenordner im Ziel, dann ein Umbenennen in
/// „<Seite> (Quill JJJJ-MM-TT)“. So entsteht nie ein halber Export, und
/// Vorhandenes wird nie überschrieben: Gibt es den Namen schon, bekommt der neue
/// Ordner einen Zähler („… 2“).
public enum ExportWriter {
    public static func write(
        _ plan: ExportPlan,
        title: String,
        untitled: String,
        into destination: URL,
        date: Date = .now,
        imageData: @Sendable (UUID) async throws -> Data?
    ) async throws -> ExportResult {
        let fileManager = FileManager()
        let staging = destination.appending(path: ".quill-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            var missing = 0
            for file in plan.files {
                let url = staging.appending(path: file.path, directoryHint: .notDirectory)
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                switch file.content {
                case .markdown(let text):
                    try Data(text.utf8).write(to: url)
                case .image(let id):
                    guard let data = try await imageData(id) else {
                        missing += 1
                        continue
                    }
                    try data.write(to: url)
                }
            }
            let folder = try moveIntoPlace(staging, title: title, untitled: untitled, in: destination, date: date, fileManager: fileManager)
            return ExportResult(
                folder: folder, pageCount: plan.pageCount,
                imageCount: plan.imageCount - missing, missingImageCount: missing
            )
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    /// Benennt den Zwischenordner in den ersten freien Namen um.
    private static func moveIntoPlace(
        _ staging: URL, title: String, untitled: String, in destination: URL, date: Date, fileManager: FileManager
    ) throws -> URL {
        var counter = 1
        while true {
            let name = ExportFileName.folderName(title: title, untitled: untitled, date: date, counter: counter)
            let target = destination.appending(path: name, directoryHint: .isDirectory)
            if !fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
                do {
                    try fileManager.moveItem(at: staging, to: target)
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
