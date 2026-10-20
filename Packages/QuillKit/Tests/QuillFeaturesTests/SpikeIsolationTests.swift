import Foundation
import Testing

/// Der Automerge-Spike (`Spikes/AutomergeSpike`, Phase 10.1, ADR-026) ist nicht Teil
/// der App: Weder die App noch QuillKit dürfen ihn oder Automerge einbinden, bis
/// das Format entschieden ist. Phase 11 lockert die Regel für Automerge selbst,
/// nicht für den Spike.
@Suite("Spike: nie in App oder QuillKit")
struct SpikeIsolationTests {
    static let root = LocalizationTests.root
    /// Alles, was in die App gebaut wird oder sie baut.
    static let productPrefixes = ["App/", "Packages/", "Quill.xcodeproj/", "QuillUITests/", "Config/"]
    static let checkedExtensions: Set<String> = [
        "swift", "pbxproj", "resolved", "xcconfig", "xcscheme", "plist", "entitlements", "xcworkspacedata",
    ]
    /// Zusammengesetzt, damit diese Datei die Begriffe nicht selbst enthält.
    static let forbidden = ["auto" + "merge", "Spikes" + "/"]

    @Test func spikeExists() {
        // Sonst prüft der zweite Test ins Leere, etwa nach einem Umzug des Spikes.
        let package = Self.root.appending(path: "Spikes/AutomergeSpike/Package.swift")
        #expect(FileManager.default.fileExists(atPath: package.path(percentEncoded: false)))
    }

    @Test func appAndQuillKitNeverReferenceTheSpike() throws {
        let ownPath = "Packages/QuillKit/Tests/QuillFeaturesTests/SpikeIsolationTests.swift"
        let files = try BundleIdentifierTests.trackedFiles().filter { path in
            path != ownPath
                && Self.productPrefixes.contains { path.hasPrefix($0) }
                && Self.checkedExtensions.contains((path as NSString).pathExtension.lowercased())
        }
        #expect(files.contains("Packages/QuillKit/Package.swift"))
        #expect(files.contains("Quill.xcodeproj/project.pbxproj"))
        var hits: [String] = []
        for path in files {
            let url = Self.root.appending(path: path)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8).lowercased()
            for term in Self.forbidden where text.contains(term.lowercased()) {
                hits.append("\(path): \(term)")
            }
        }
        #expect(hits.isEmpty, "Spike oder Automerge eingebunden: \(hits.joined(separator: ", "))")
    }
}
