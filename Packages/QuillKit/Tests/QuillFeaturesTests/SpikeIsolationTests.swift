import Foundation
import Testing

/// Der Automerge-Spike (`Spikes/AutomergeSpike`, Phase 10.1, ADR-026) ist nicht Teil
/// der App: Weder die App noch QuillKit dürfen ihn einbinden. Automerge selbst steht
/// seit Phase 11 nur in QuillSync, seinen Tests und den Paket-Dateien
/// (`AutomergeIsolationTests` prüft die Importe).
@Suite("Spike: nie in App oder QuillKit")
struct SpikeIsolationTests {
    static let root = LocalizationTests.root
    /// Alles, was in die App gebaut wird oder sie baut.
    static let productPrefixes = ["App/", "Packages/", "Quill.xcodeproj/", "QuillUITests/", "Config/"]
    static let checkedExtensions: Set<String> = [
        "swift", "pbxproj", "resolved", "xcconfig", "xcscheme", "plist", "entitlements", "xcworkspacedata",
    ]
    /// Zusammengesetzt, damit diese Datei die Begriffe nicht selbst enthält.
    static let spike = "Spikes" + "/"
    static let automerge = "auto" + "merge"
    /// Nur hier darf Automerge vorkommen: Paket, aufgelöste Versionen, QuillSync und seine Tests.
    static let automergeAllowed = [
        "Packages/QuillKit/Package.swift",
        "Packages/QuillKit/Package.resolved",
        "Quill.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        "Packages/QuillKit/Sources/QuillSync/",
        "Packages/QuillKit/Tests/QuillSyncTests/",
        "Packages/QuillKit/Tests/QuillFeaturesTests/AutomergeIsolationTests.swift",
        // Prüft die Paketnamen in den Lizenztexten, importiert nichts.
        "Packages/QuillKit/Tests/QuillFeaturesTests/ThirdPartyLicensesTests.swift",
        // Nutzt nur die Importprüfung von AutomergeIsolationTests, importiert nichts.
        "Packages/QuillKit/Tests/QuillFeaturesTests/AIIsolationTests.swift",
        // Nutzt nur die Importprüfung von AutomergeIsolationTests, importiert nichts.
        "Packages/QuillKit/Tests/QuillFeaturesTests/UpdateIsolationTests.swift",
    ]

    @Test func spikeExists() {
        // Sonst prüft der zweite Test ins Leere, etwa nach einem Umzug des Spikes.
        let package = Self.root.appending(path: "Spikes/AutomergeSpike/Package.swift")
        #expect(FileManager.default.fileExists(atPath: package.path(percentEncoded: false)))
    }

    @Test func spikeNeverAndAutomergeOnlyInQuillSync() throws {
        let ownPath = "Packages/QuillKit/Tests/QuillFeaturesTests/SpikeIsolationTests.swift"
        let files = try Self.productFiles(excluding: ownPath)
        var hits: [String] = []
        for path in files {
            let text = try Self.text(of: path)
            if text.contains(Self.spike.lowercased()) { hits.append("\(path): \(Self.spike)") }
            if text.contains(Self.automerge), !Self.automergeAllowed.contains(where: { path.hasPrefix($0) }) {
                hits.append("\(path): \(Self.automerge)")
            }
        }
        #expect(hits.isEmpty, "Spike oder Automerge außerhalb von QuillSync: \(hits.joined(separator: ", "))")
    }

    @Test func automergeIsPinnedInBothResolvedFiles() throws {
        // Version und Revision wie in ADR-026; Xcode und SwiftPM lösen getrennt auf.
        for path in ["Packages/QuillKit/Package.resolved", "Quill.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"] {
            let text = try Self.text(of: path)
            #expect(text.contains("aa45d17ac92cef2b8ded63b47e65a28dc85e3418"), "\(path)")
            #expect(text.contains(#""version" : "0.7.2""#), "\(path)")
        }
    }

    /// Alle versionierten Dateien, die in die App gebaut werden oder sie bauen.
    static func productFiles(excluding ownPath: String) throws -> [String] {
        let files = try BundleIdentifierTests.trackedFiles().filter { path in
            path != ownPath
                && Self.productPrefixes.contains { path.hasPrefix($0) }
                && Self.checkedExtensions.contains((path as NSString).pathExtension.lowercased())
                && FileManager.default.fileExists(atPath: Self.root.appending(path: path).path(percentEncoded: false))
        }
        #expect(files.contains("Packages/QuillKit/Package.swift"))
        #expect(files.contains("Quill.xcodeproj/project.pbxproj"))
        return files
    }

    static func text(of path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8).lowercased()
    }
}
