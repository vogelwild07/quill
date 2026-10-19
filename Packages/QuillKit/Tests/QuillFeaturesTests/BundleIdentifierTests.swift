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
    /// Ordner, die nicht zum Quelltext gehören (Builds, Ausgaben, lokale Entwürfe).
    static let skippedDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", "build", "DerivedData", "dist", "xcuserdata", "IconDrafts",
    ]

    @Test func oldIdentifierIsGone() throws {
        var hits: [String] = []
        let enumerator = try #require(FileManager.default.enumerator(
            at: Self.root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]
        ))
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                if Self.skippedDirectories.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true,
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  text.contains(Self.oldPrefix) else { continue }
            let path = String(url.path(percentEncoded: false).dropFirst(Self.root.path(percentEncoded: false).count))
            if !Self.allowedFiles.contains(path) { hits.append(path) }
        }
        #expect(hits.isEmpty, "Alte Kennung in: \(hits.sorted().joined(separator: ", "))")
    }

    @Test func everyTargetUsesTheNewPrefix() throws {
        let project = try String(
            contentsOf: Self.root.appending(path: "Quill.xcodeproj/project.pbxproj"), encoding: .utf8
        )
        let identifiers = project.split(separator: "\n")
            .filter { $0.contains("PRODUCT_BUNDLE_IDENTIFIER = ") }
            .map { $0.split(separator: "=")[1].trimmingCharacters(in: CharacterSet(charactersIn: " ;\"")) }
        #expect(identifiers.count == 6)
        for identifier in identifiers {
            #expect(identifier == Self.prefix || identifier.hasPrefix(Self.prefix + "."), "\(identifier)")
        }
    }
}
