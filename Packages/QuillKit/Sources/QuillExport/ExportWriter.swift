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
///
/// Der Zwischenordner liegt im temporären Ordner, den das System für das Ziel
/// vorsieht (`.itemReplacementDirectory`; in der Sandbox im Container der App), wenn
/// er auf demselben Volume liegt: Dann bleibt nach einem Absturz nichts im Ziel, und
/// das Umbenennen ist ein Schritt. Sonst (andere Volumes) entsteht er als
/// `.quill-export-<UUID>` im Ziel; alte Reste davon räumt der nächste Export weg.
public enum ExportWriter {
    /// Name des Zwischenordners im Ziel, wenn der Systemordner nicht passt.
    static let stagingPrefix = ".quill-export-"
    /// Ältere Zwischenordner im Ziel gelten als Rest eines abgebrochenen Exports.
    /// Jüngere könnten zu einem Export gehören, der in einem anderen Fenster läuft.
    static let staleStagingAge: TimeInterval = 3600

    public static func export(
        _ root: PageExportSnapshot,
        strings: ExportStrings,
        into destination: URL,
        date: Date = .now,
        imageData: @Sendable (UUID) async throws -> Data?
    ) async throws -> ExportResult {
        try await export(root, strings: strings, into: destination, date: date, preferSystemTemporary: true, imageData: imageData)
    }

    /// `preferSystemTemporary: false` erzwingt den Zwischenordner im Ziel (Tests).
    static func export(
        _ root: PageExportSnapshot,
        strings: ExportStrings,
        into destination: URL,
        date: Date,
        preferSystemTemporary: Bool,
        imageData: @Sendable (UUID) async throws -> Data?
    ) async throws -> ExportResult {
        let fileManager = FileManager()
        let staging = try makeStaging(for: destination, preferSystemTemporary: preferSystemTemporary, fileManager: fileManager)
        defer { try? fileManager.removeItem(at: staging) }
        // `export/` wird am Ende umbenannt, `images/` hält die Bilder bis dahin.
        let output = staging.appending(path: "export", directoryHint: .isDirectory)
        let images = staging.appending(path: "images", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: images, withIntermediateDirectories: false)

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

    /// Leerer Zwischenordner für einen Export nach `destination`.
    private static func makeStaging(for destination: URL, preferSystemTemporary: Bool, fileManager: FileManager) throws -> URL {
        if preferSystemTemporary,
           let system = try? fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true) {
            if isSameVolume(system, destination) { return system }
            // Über Volumes hinweg wäre das Umbenennen ein Kopieren, das halb scheitern kann.
            try? fileManager.removeItem(at: system)
        }
        removeStaleStaging(in: destination, fileManager: fileManager)
        let staging = destination.appending(path: stagingPrefix + UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        return staging
    }

    private static func isSameVolume(_ first: URL, _ second: URL) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let a = try? first.resourceValues(forKeys: key).volumeIdentifier,
              let b = try? second.resourceValues(forKeys: key).volumeIdentifier else { return false }
        return a.isEqual(b)
    }

    /// Löscht im Ziel nur Ordner, die exakt `.quill-export-<UUID>` heißen (UUID wie
    /// Quill sie schreibt) und älter als `staleStagingAge` sind. Alles andere bleibt.
    static func removeStaleStaging(in destination: URL, now: Date = .now, fileManager: FileManager) {
        let names = (try? fileManager.contentsOfDirectory(atPath: destination.path(percentEncoded: false))) ?? []
        for name in names where isStagingName(name) {
            let url = destination.appending(path: name, directoryHint: .isDirectory)
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) > staleStagingAge else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    static func isStagingName(_ name: String) -> Bool {
        guard name.hasPrefix(stagingPrefix) else { return false }
        let rest = String(name.dropFirst(stagingPrefix.count))
        return UUID(uuidString: rest)?.uuidString == rest
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
