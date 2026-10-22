import Foundation
import Testing

/// Lokale KI nur in QuillAI und nur auf dem Gerät (ADR-032): Kein anderes Modul
/// importiert FoundationModels, und nirgends steht das Modell von Private Cloud Compute,
/// das Anfragen an Server schickt.
@Suite("KI nur in QuillAI, nur auf dem Gerät")
struct AIIsolationTests {
    static let root = LocalizationTests.root
    static let directories = ["App", "Packages/QuillKit/Sources", "Packages/QuillKit/Tests", "QuillUITests"]

    static func allSwiftFiles() throws -> [String] {
        try directories.flatMap { try AutomergeIsolationTests.swiftFiles(under: $0) }
    }

    @Test func onlyQuillAIImportsFoundationModels() throws {
        let files = try Self.allSwiftFiles()
        var importers: [String] = []
        for path in files {
            let text = try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
            if AutomergeIsolationTests.importedModules(text).contains(where: { $0.contains("FoundationModels") }) {
                importers.append(path)
            }
        }
        #expect(importers.contains { $0.hasPrefix("Packages/QuillKit/Sources/QuillAI/") })
        let outside = importers.filter { !$0.hasPrefix("Packages/QuillKit/Sources/QuillAI/") }
        #expect(outside.isEmpty, "FoundationModels außerhalb von QuillAI: \(outside.joined(separator: ", "))")
    }

    @Test func nothingUsesTheServerModel() throws {
        // Zusammengesetzt, damit diese Datei sich nicht selbst findet.
        let forbidden = "PrivateCloud" + "Compute"
        var hits: [String] = []
        for path in try Self.allSwiftFiles() {
            let text = try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
            if text.contains(forbidden) { hits.append(path) }
        }
        #expect(hits.isEmpty, "Private Cloud Compute in: \(hits.joined(separator: ", "))")
    }
}
