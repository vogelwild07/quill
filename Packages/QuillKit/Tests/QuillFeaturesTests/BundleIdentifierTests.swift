import Foundation
import Testing

/// Die Bundle-ID ist `io.github.vogelwild07.quill` (ADR-022). Die alte Kennung darf
/// nur noch in der Doku zum Umzug stehen, sonst landet sie wieder in Kennungen
/// für Zwischenablage, Logger oder Container.
@Suite("Bundle-ID: nur io.github.vogelwild07.quill")
struct BundleIdentifierTests {
    static let root = LocalizationTests.root
    static let prefix = "io.github.vogelwild07.quill"
    /// Zusammengesetzt, damit diese Datei die alte Kennung nicht selbst enthält.
    static let oldPrefix = "de." + "vogel"
    /// Beschreiben den Umzug aus dem alten Container (`docs/data-model.md`, ADR-022).
    static let allowedFiles: Set<String> = ["docs/data-model.md", "docs/decisions.md"]

    /// Nur Dateien im Repo, wie `git ls-files` sie nennt: Ignorierte lokale Dateien
    /// (`Config/Local.xcconfig`, Builds, Entwürfe) gehören nicht dazu.
    static func trackedFiles() throws -> [String] {
        let git = Process()
        git.executableURL = URL(filePath: "/usr/bin/git")
        git.arguments = ["-C", root.path(percentEncoded: false), "ls-files", "-z"]
        let output = Pipe()
        git.standardOutput = output
        try git.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        try #require(git.terminationStatus == 0, "git ls-files gescheitert")
        return String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
    }

    @Test func oldIdentifierIsGone() throws {
        let files = try Self.trackedFiles()
        #expect(files.contains("Quill.xcodeproj/project.pbxproj"), "git ls-files liefert nicht das Repo")
        // Byteweise statt als UTF-8: Auch Binärdateien und andere Kodierungen zählen.
        let old = Data(Self.oldPrefix.utf8)
        let hits = try files.filter { path in
            guard !Self.allowedFiles.contains(path) else { return false }
            // Gelöscht, aber noch nicht gestagt: `git ls-files` nennt die Datei weiter,
            // sie kann die alte Kennung aber nicht mehr enthalten.
            let url = Self.root.appending(path: path)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return false }
            return try Data(contentsOf: url).range(of: old) != nil
        }
        #expect(hits.isEmpty, "Alte Kennung in: \(hits.joined(separator: ", "))")
    }

    @Test func everyTargetUsesTheNewPrefix() throws {
        let project = try String(
            contentsOf: Self.root.appending(path: "Quill.xcodeproj/project.pbxproj"), encoding: .utf8
        )
        let identifiers = project.split(separator: "\n")
            .compactMap { line -> String? in
                guard let range = line.range(of: "PRODUCT_BUNDLE_IDENTIFIER = ") else { return nil }
                return line[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " ;\""))
            }
        // App (Debug, Release), Profiling-App, UI-Tests (Debug, Release), Profiling-UI-Tests.
        #expect(identifiers.count == 6)
        for identifier in identifiers {
            #expect(identifier == Self.prefix || identifier.hasPrefix(Self.prefix + "."), "\(identifier)")
        }
    }
}
