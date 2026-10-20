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
        // App (Debug, Release), Profiling-App, Synctest A und B, UI-Tests (Debug, Release),
        // Profiling-UI-Tests, Synctest-UI-Tests A und B.
        #expect(identifiers.count == 10)
        for identifier in identifiers {
            #expect(identifier == Self.prefix || identifier.hasPrefix(Self.prefix + "."), "\(identifier)")
        }
    }

    /// Die beiden Testvarianten für den Sync (`Scripts/make-synctest.sh`, ADR-029) haben
    /// je eine eigene Kennung und damit einen eigenen Container. Hätte eine die Kennung
    /// der echten App, schriebe der Handtest in den echten Store.
    @Test func synctestVariantsNeverUseTheRealIdentifier() throws {
        let project = try String(
            contentsOf: Self.root.appending(path: "Quill.xcodeproj/project.pbxproj"), encoding: .utf8
        )
        let app = BuildSettings.configurations(in: project)
            .filter { $0.settings["INFOPLIST_KEY_CFBundleDisplayName"] != nil }
        let variants = app.filter { $0.name.hasPrefix("Synctest") }
        #expect(variants.map(\.name).sorted() == ["SynctestA", "SynctestB"])
        for variant in variants {
            let identifier = try #require(variant.settings["PRODUCT_BUNDLE_IDENTIFIER"], "\(variant.name)")
            let letter = variant.name.dropFirst("Synctest".count).lowercased()
            #expect(identifier != Self.prefix, "\(variant.name) nutzt die Kennung der echten App")
            #expect(identifier == "\(Self.prefix).synctest.\(letter)", "\(variant.name): \(identifier)")
            #expect(variant.settings["PRODUCT_NAME"] == "Quill Synctest \(letter.uppercased())")
        }
        // Das Skript baut genau diese Konfigurationen und prüft die Kennung im Ergebnis.
        let script = try String(contentsOf: Self.root.appending(path: "Scripts/make-synctest.sh"), encoding: .utf8)
        #expect(script.contains("for variant in A B"))
        #expect(script.contains(#"$real.synctest.$lower"#))
    }
}
