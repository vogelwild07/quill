import Foundation
import Testing

/// Lizenztexte der Bausteine anderer (ADR-029): Die Datei passt zur festgelegten
/// Version von automerge-swift und enthält die Rust-Pakete des vorgebauten Kerns.
/// Nach einem Versionswechsel neu erzeugen: `python3 Scripts/third-party-licenses.py`.
@Suite("Lizenzen: passend zu automerge-swift")
struct ThirdPartyLicensesTests {
    static let root = LocalizationTests.root

    func text(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
    }

    @Test func licensesMatchThePinnedVersion() throws {
        let package = try text("Packages/QuillKit/Package.swift")
        let pinned = try #require(package.firstMatch(of: /automerge-swift\.git", exact: "([0-9.]+)"/)?.1)
        let licenses = try text("Packages/QuillKit/Sources/QuillFeatures/Resources/ThirdPartyLicenses.txt")
        #expect(licenses.hasPrefix("automerge-swift \(pinned) "), "Lizenzen für eine andere Version von automerge-swift")
        #expect(licenses.contains("Rust-Pakete im vorgebauten Automerge-Kern (automergeFFI aus automerge-swift \(pinned))"))
        // Stichproben: Kern, Bindung (MPL-2.0) und ein Paket mit eigener Lizenzdatei.
        for line in ["automerge 0.7.2: MIT", "uniffi_core 0.28.2: MPL-2.0", "flate2 1.0.30: MIT OR Apache-2.0"] {
            #expect(licenses.contains(line + "\n"), "\(line)")
        }
        #expect(licenses.contains("Mozilla Public License Version 2.0"))
        #expect(licenses.contains("the Automerge contributors"))
    }
}
