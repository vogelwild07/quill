import Foundation
import Testing

/// Maße der Sync-Hinweise nur aus `QuillDesign` (CLAUDE.md, `docs/design.md`), keine
/// Zahlen für Abstände, Ränder, Radien und Deckkraft in den Ansichten.
@Suite("Design-Tokens")
struct DesignTokenTests {
    static let files = ["Sources/QuillFeatures/Sync/ConflictViews.swift"]

    @Test(arguments: files)
    func layoutValuesComeFromTokens(_ file: String) throws {
        let package = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: package.appending(path: file), encoding: .utf8)
        let literal = /(spacing|minLength|cornerRadius|width|height):\s*[0-9]|\.(padding|opacity)\([^)]*[0-9]/
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .filter { $0.element.contains(literal) }.map { "\($0.offset + 1): \($0.element.trimmingCharacters(in: .whitespaces))" }
        #expect(lines.isEmpty, "\(file)")
    }
}
