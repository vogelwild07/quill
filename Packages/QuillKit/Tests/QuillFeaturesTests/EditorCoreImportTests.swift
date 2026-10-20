import Foundation
import Testing

/// `QuillEditorCore` bleibt ohne Oberfläche und ohne Plattform (ADR-028): Mac und
/// iPhone teilen Dokument, Speichern und Theme-Rechnung. Nur diese Importe sind
/// erlaubt; alles mit AppKit, UIKit oder SwiftUI gehört nach QuillEditor.
@Suite("Editor-Kern: ohne AppKit, UIKit und SwiftUI")
struct EditorCoreImportTests {
    static let root = LocalizationTests.root
    static let sources = "Packages/QuillKit/Sources/QuillEditorCore"
    static let allowed: Set<String> = ["Foundation", "Observation", "Synchronization", "QuillModel"]
    static let importKinds: Set<String> = ["struct", "class", "enum", "protocol", "typealias", "func", "var", "let"]

    @Test func coreImportsNoPlatformFramework() throws {
        let directory = Self.root.appending(path: Self.sources)
        let files = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        // Sonst prüft der Test ins Leere, etwa nach einem Umzug des Kerns.
        #expect(files.count >= 10, "nur \(files.count) Dateien in \(Self.sources)")
        var hits: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for (number, line) in lines.enumerated() {
                // `import X`, auch mit Attributen (`@testable`, `@preconcurrency`) oder Art (`import struct X.Y`).
                let words = line.split(separator: " ").filter { !$0.hasPrefix("@") }
                guard words.first == "import", words.count >= 2 else { continue }
                let target = Self.importKinds.contains(String(words[1])) && words.count >= 3 ? words[2] : words[1]
                let module = String(target.split(separator: ".").first ?? target)
                if !Self.allowed.contains(module) {
                    hits.append("\(file.lastPathComponent):\(number + 1): import \(module)")
                }
            }
        }
        #expect(hits.isEmpty, "Nicht erlaubt im Kern: \(hits.joined(separator: ", "))")
    }

    @Test func coreDependsOnlyOnTheModel() throws {
        let package = try String(contentsOf: Self.root.appending(path: "Packages/QuillKit/Package.swift"), encoding: .utf8)
        #expect(package.contains(#".target(name: "QuillEditorCore", dependencies: ["QuillModel"])"#))
    }
}
