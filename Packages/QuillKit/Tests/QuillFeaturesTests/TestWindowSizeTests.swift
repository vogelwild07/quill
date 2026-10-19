#if canImport(AppKit) && DEBUG
import Foundation
import Testing
@testable import QuillFeatures

/// Fenstergröße für die README-Bilder (`-QuillWindowSize`): nur mit gültiger Angabe.
@MainActor
@Suite struct TestWindowSizeTests {
    @Test func readsSizeFromArguments() {
        #expect(TestWindowSize.size(arguments: ["Quill", "-QuillWindowSize", "1180x760"]) == CGSize(width: 1180, height: 760))
        #expect(TestWindowSize.size(arguments: ["Quill"]) == nil)
        #expect(TestWindowSize.size(arguments: ["Quill", "-QuillWindowSize"]) == nil)
    }

    @Test(arguments: ["", "1180", "1180x", "x760", "axb", "399x760", "1180x4001", "1180x760x2"])
    func rejectsInvalidSpec(_ spec: String) {
        #expect(TestWindowSize.size(arguments: ["-QuillWindowSize", spec]) == nil)
    }
}
#endif
