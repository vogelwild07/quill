#if canImport(AppKit) && DEBUG
import AppKit
@testable import QuillEditor
import Testing

/// Eigene Zwischenablage für UI-Tests (`-QuillPasteboardName`): nur aus der
/// Kommandozeile, nie aus gespeicherten Einstellungen (wie ADR-019).
@MainActor
@Suite("Editor: Zwischenablage aus dem Startargument", .serialized)
struct ClipboardArgumentTests {
    @Test func nameComesFromCommandLine() {
        #expect(BlockTextView.clipboardName(arguments: ["Quill", "-QuillPasteboardName", "uitest"]) == "uitest")
        #expect(BlockTextView.clipboardName(arguments: ["Quill", "-QuillPasteboardName"]) == nil)
        #expect(BlockTextView.clipboardName(arguments: ["Quill", "-QuillPasteboardName", ""]) == nil)
        #expect(BlockTextView.clipboardName(arguments: ["Quill"]) == nil)
    }

    /// Ein gespeicherter Wert (wie nach `defaults write`) leitet nichts um.
    @Test func savedDefaultIsIgnored() {
        let defaults = UserDefaults.standard
        defaults.set("gespeichert", forKey: BlockTextView.pasteboardArgument)
        defer { defaults.removeObject(forKey: BlockTextView.pasteboardArgument) }
        #expect(defaults.string(forKey: BlockTextView.pasteboardArgument) == "gespeichert", "Vorbedingung")
        #expect(BlockTextView.clipboardName(arguments: ["Quill"]) == nil)
    }
}
#endif
