#if canImport(AppKit)
import AppKit
@testable import QuillFeatures
import Testing

/// Fenster der Schnellnotiz (ADR-036): Glas nur mit aktivem Regler, bei „Wie System“ die
/// Fensterfläche wie vor Phase 19.
@MainActor
@Suite("Schnellnotiz: Glas nach dem Regler")
struct QuickNoteGlassTests {
    private func makePanel() -> NSPanel {
        NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: true)
    }

    @Test func followsSystemKeepsTheWindowBackground() {
        let panel = makePanel()
        QuickNoteMenuBar.applyGlass(false, to: panel)
        #expect(!panel.styleMask.contains(.fullSizeContentView))
        #expect(!panel.titlebarAppearsTransparent)
        #expect(panel.isOpaque)
        #expect(panel.backgroundColor == .windowBackgroundColor)
    }

    @Test func customGlassAndBackAgain() {
        let panel = makePanel()
        QuickNoteMenuBar.applyGlass(true, to: panel)
        #expect(panel.styleMask.contains(.fullSizeContentView))
        #expect(panel.titlebarAppearsTransparent)
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)

        QuickNoteMenuBar.applyGlass(false, to: panel)
        #expect(!panel.styleMask.contains(.fullSizeContentView))
        #expect(panel.isOpaque)
        #expect(panel.backgroundColor == .windowBackgroundColor)
    }
}
#endif
