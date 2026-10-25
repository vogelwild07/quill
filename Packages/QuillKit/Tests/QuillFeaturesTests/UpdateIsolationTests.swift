import Foundation
import Testing

/// Sparkle und Netz nur in QuillUpdate (ADR-037): Kein anderes Modul importiert Sparkle
/// oder öffnet eine Verbindung. Einzige Ausnahme ist der Testserver der UI-Tests auf
/// 127.0.0.1, der zählt, ob die App bei ausgeschaltetem Schalter fragt.
@Suite("Sparkle und Netz nur in QuillUpdate")
struct UpdateIsolationTests {
    static let root = LocalizationTests.root
    static let updateSources = "Packages/QuillKit/Sources/QuillUpdate/"
    static let allowedImporters = [updateSources, "Packages/QuillKit/Tests/QuillUpdateTests/"]
    static let testServer = "QuillUITests/UpdateTestServer.swift"
    /// Zusammengesetzt, damit diese Datei sich nicht selbst findet.
    static let networkWords = ["URL" + "Session", "NW" + "Listener", "NW" + "Connection", "CF" + "Socket", "CFStream" + "CreatePair"]

    @Test func onlyQuillUpdateImportsSparkle() throws {
        var importers: [String] = []
        for path in try AIIsolationTests.allSwiftFiles() {
            let text = try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
            if AutomergeIsolationTests.importedModules(text).contains("Sparkle") { importers.append(path) }
        }
        #expect(importers.contains { $0.hasPrefix(Self.updateSources) })
        let outside = importers.filter { path in !Self.allowedImporters.contains { path.hasPrefix($0) } }
        #expect(outside.isEmpty, "Sparkle außerhalb von QuillUpdate: \(outside.joined(separator: ", "))")
    }

    /// Quill selbst öffnet keine Verbindung; das tut nur Sparkle aus QuillUpdate heraus.
    @Test func nothingElseOpensAConnection() throws {
        var hits: [String] = []
        for path in try AIIsolationTests.allSwiftFiles() where path != Self.testServer {
            let text = try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
            let modules = AutomergeIsolationTests.importedModules(text)
            if modules.contains("Network") || Self.networkWords.contains(where: text.contains) { hits.append(path) }
        }
        #expect(hits.isEmpty, "Netz außerhalb von Sparkle: \(hits.joined(separator: ", "))")
    }

    @Test func onlyQuillUpdateDependsOnSparkle() throws {
        let package = try String(contentsOf: Self.root.appending(path: "Packages/QuillKit/Package.swift"), encoding: .utf8)
        let product = #".product(name: "Sparkle", package: "Sparkle""#
        #expect(package.components(separatedBy: product).count - 1 == 1, "Sparkle genau einmal als Abhängigkeit")
        let target = #/\.target\(\s*name:\s*"QuillUpdate",\s*dependencies:\s*\[([^\]]*)\]/#
        let match = try #require(package.firstMatch(of: target))
        #expect(match.1.contains(product))
    }
}
