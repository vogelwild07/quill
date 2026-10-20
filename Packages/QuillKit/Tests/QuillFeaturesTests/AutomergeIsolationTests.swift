import Foundation
import Testing

/// Automerge steht nur in QuillSync (ADR-026, Ausstiegsplan): Kein anderes Modul
/// importiert es, und die öffentliche Schnittstelle von QuillSync zeigt keine
/// Automerge-Typen. Ein Wechsel des CRDT bleibt so auf dieses Modul beschränkt.
@Suite("Automerge nur in QuillSync")
struct AutomergeIsolationTests {
    static let root = LocalizationTests.root
    static let allowedImporters = ["Packages/QuillKit/Sources/QuillSync/", "Packages/QuillKit/Tests/QuillSyncTests/"]
    /// Typen von automerge-swift, die nicht nach außen dürfen.
    static let automergeTypes = [
        "ObjId", "Document", "ChangeHash", "ActorId", "ScalarValue", "Value", "Mark", "Patch", "SyncState", "ExpandMark", "Cursor",
    ]

    static func swiftFiles(under directory: String) throws -> [String] {
        let base = root.appending(path: directory)
        let enumerator = try #require(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { directory + "/" + $0.path(percentEncoded: false).dropFirst(base.path(percentEncoded: false).count).trimmingPrefix("/") }
    }

    /// Module aus `import`-Zeilen, auch mit Attributen oder Art (`import struct X.Y`).
    static func importedModules(_ text: String) -> [String] {
        let kinds: Set<String> = ["struct", "class", "enum", "protocol", "typealias", "func", "var", "let"]
        return text.split(separator: "\n").compactMap { line in
            let words = line.split(whereSeparator: \.isWhitespace).filter { !$0.hasPrefix("@") }
            guard words.first == "import", words.count >= 2 else { return nil }
            let target = kinds.contains(String(words[1])) && words.count >= 3 ? words[2] : words[1]
            return String(target.split(separator: ".").first ?? target)
        }
    }

    @Test func onlyQuillSyncImportsAutomerge() throws {
        var files: [String] = []
        for directory in ["App", "Packages/QuillKit/Sources", "Packages/QuillKit/Tests", "QuillUITests"] {
            files += try Self.swiftFiles(under: directory)
        }
        #expect(files.contains { $0.hasPrefix("Packages/QuillKit/Sources/QuillSync/") })
        var importers: [String] = []
        for path in files {
            let text = try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
            if Self.importedModules(text).contains("Automerge") { importers.append(path) }
        }
        #expect(importers.contains { $0.hasPrefix("Packages/QuillKit/Sources/QuillSync/") })
        let outside = importers.filter { path in !Self.allowedImporters.contains { path.hasPrefix($0) } }
        #expect(outside.isEmpty, "Automerge außerhalb von QuillSync: \(outside.joined(separator: ", "))")
    }

    @Test func publicInterfaceShowsNoAutomergeTypes() throws {
        let pattern = try Regex("\\b(" + Self.automergeTypes.joined(separator: "|") + ")\\b")
        var hits: [String] = []
        for path in try Self.swiftFiles(under: "Packages/QuillKit/Sources/QuillSync") {
            let lines = try String(contentsOf: Self.root.appending(path: path), encoding: .utf8).split(separator: "\n")
            for (number, line) in lines.enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard ["public ", "open ", "package "].contains(where: code.hasPrefix) else { continue }
                if code.contains(pattern) { hits.append("\((path as NSString).lastPathComponent):\(number + 1)") }
            }
        }
        #expect(hits.isEmpty, "Automerge-Typ in der Schnittstelle: \(hits.joined(separator: ", "))")
    }

    @Test func onlyTheSyncTargetsDependOnAutomerge() throws {
        let package = try String(contentsOf: Self.root.appending(path: "Packages/QuillKit/Package.swift"), encoding: .utf8)
        let product = #".product(name: "Automerge", package: "automerge-swift")"#
        #expect(package.components(separatedBy: product).count - 1 == 1, "Automerge genau einmal als Abhängigkeit")
        let target = #/\.target\(\s*name:\s*"QuillSync",\s*dependencies:\s*\[([^\]]*)\]/#
        let match = try #require(package.firstMatch(of: target))
        #expect(match.1.contains(product))
    }
}
