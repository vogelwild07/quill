#if canImport(AppKit)
import AppKit
import ImageIO
import QuillModel
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import QuillEditor

/// Bild-Blöcke im Editor mit echtem `PageStore` (im Arbeitsspeicher). Testbilder
/// werden im Test erzeugt; Zwischenablagen sind eigene, nie die allgemeine.
@MainActor
@Suite("Editor: Bild-Blöcke", .serialized)
struct ImageBlockEditorTests {
    let window: NSWindow
    let editor: BlockEditorController
    let store: PageStore

    init() throws {
        store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        editor = BlockEditorController(document: EditorDocument(blocks: [EditorBlock(text: "Text"), EditorBlock()]))
        editor.imageStore = store
        window.contentView = editor.scrollView
        editor.focus()
    }

    static func png(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    }

    /// Rauschen lässt sich kaum komprimieren: ergibt ein PNG über 20 MB. Dauert,
    /// deshalb nicht auf dem Main Actor (sonst stocken parallele Tests).
    nonisolated static func heavyPNG() -> Data {
        let width = 2700, height = 2700
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        arc4random_buf(&bytes, bytes.count)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    private func pasteboard() -> NSPasteboard { NSPasteboard(name: .init("de.vogel.quill.tests.\(UUID().uuidString)")) }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(10)
        while !condition() {
            #expect(Date.now < deadline, "Zeitüberschreitung")
            guard Date.now < deadline else { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private var kinds: [BlockKind] { editor.document.blocks.map(\.kind) }

    private func insert(_ data: Data, at position: BlockPosition) async throws {
        editor.insertImages([.data(data)], from: position, to: position)
        try await waitUntil { editor.pendingImports.isEmpty }
    }

    /// PNG als Datei im Temp-Ordner des Tests, wie aus dem Finder.
    private func pngFile(width: Int = 30, height: Int = 30) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "quill-test-\(UUID().uuidString).png")
        try Self.png(width: width, height: height).write(to: url)
        return url
    }

    private func undo() {
        editor.textView.breakUndoCoalescing()
        editor.undoManager.undo()
    }

    @Test func insertingReplacesEmptyParagraphAndIsUndoable() async throws {
        try await insert(Self.png(width: 40, height: 20), at: BlockPosition(block: 1, offset: 0))
        #expect(kinds == [.paragraph, .image, .paragraph])
        let assetID = try #require(editor.document[1].assetID)
        #expect(try await store.imageData(assetID) != nil)
        #expect(editor.position(atCharacter: editor.textView.selectedRange().location) == BlockPosition(block: 2, offset: 0))

        undo()
        #expect(kinds == [.paragraph, .paragraph])
        editor.undoManager.redo()
        #expect(kinds == [.paragraph, .image, .paragraph])
        #expect(editor.document[1].assetID == assetID)
    }

    @Test func loadedImageGetsItsSizeAfterLoading() async throws {
        let imported = try await store.importImage(Self.png(width: 200, height: 100))
        editor.load(EditorDocument(blocks: [EditorBlock(kind: .image, properties: BlockProperties(assetID: imported.assetID)), EditorBlock()]))
        try await waitUntil { EditorImageCache.shared.entry(for: imported.assetID) != nil }
        #expect(EditorImageCache.shared.entry(for: imported.assetID)?.pointSize == CGSize(width: 200, height: 100))

        editor.textView.layoutSubtreeIfNeeded()
        var height: CGFloat = 0
        editor.textView.textLayoutManager?.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            height = fragment.layoutFragmentFrame.height
            return false
        }
        // 100 pt Bild statt 120 pt Platzhalter, plus Absatzabstände.
        #expect(height > 100 && height < ImageAttachment.placeholderHeight)
    }

    @Test func pastingImageDataInsertsImageBlock() async throws {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setData(Self.png(width: 30, height: 30), forType: .png)
        editor.textView.setSelectedRange(NSRange(location: editor.characterLocation(of: BlockPosition(block: 1, offset: 0)), length: 0))
        #expect(editor.paste(from: board))
        try await waitUntil { kinds.contains(.image) }
        #expect(kinds == [.paragraph, .image, .paragraph])
    }

    @Test func textWithImageIsPastedAsText() async throws {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("Hallo", forType: .string)
        item.setData(Self.png(width: 10, height: 10), forType: .tiff)
        board.clearContents()
        board.writeObjects([item])
        editor.textView.setSelectedRange(NSRange(location: editor.characterLocation(of: BlockPosition(block: 1, offset: 0)), length: 0))
        #expect(editor.paste(from: board))
        #expect(editor.document[1].text == "Hallo")
        #expect(!kinds.contains(.image))
    }

    @Test func pastingCopiedImageBlockDuplicatesAsset() async throws {
        try await insert(Self.png(width: 40, height: 20), at: BlockPosition(block: 1, offset: 0))
        let original = try #require(editor.document[1].assetID)
        try await waitUntil { EditorImageCache.shared.entry(for: original) != nil }

        let start = editor.characterLocation(of: BlockPosition(block: 1, offset: 0))
        editor.textView.setSelectedRange(NSRange(location: start, length: 1))
        let board = pasteboard()
        defer { board.releaseGlobally() }
        #expect(editor.copySelection(to: board))
        // Für andere Apps liegt das Bild auch als PNG bereit.
        #expect(board.data(forType: .png) != nil)

        editor.textView.setSelectedRange(NSRange(location: editor.characterLocation(of: BlockPosition(block: 2, offset: 0)), length: 0))
        #expect(editor.paste(from: board))
        try await waitUntil { kinds.filter { $0 == .image }.count == 2 }
        let ids = editor.document.blocks.compactMap(\.assetID)
        try #require(ids.count == 2)
        #expect(ids[0] == original && ids[1] != original)
        #expect(try await store.imageData(ids[1])?.data == store.imageData(original)?.data)
    }

    @Test func heavyImageIsDownscaledWithNotice() async throws {
        let data = await Task.detached { Self.heavyPNG() }.value
        #expect(data.count > ImageImport.maxOriginalBytes)
        try await insert(data, at: BlockPosition(block: 1, offset: 0))
        #expect(kinds == [.paragraph, .image, .paragraph])
        #expect(!editor.noticeView.isHidden)
        #expect(editor.noticeView.text == "Bild wurde verkleinert")
    }

    @Test func unreadableImageRemovesPlaceholderWithNotice() async throws {
        try await insert(Data("kein Bild".utf8), at: BlockPosition(block: 1, offset: 0))
        #expect(kinds == [.paragraph, .paragraph])
        #expect(!editor.noticeView.isHidden)
    }

    // MARK: Platzhalter, Undo während des Imports, Auswahl

    @Test func pastedFileShowsPlaceholderUntilImported() async throws {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects([try pngFile() as NSURL])
        editor.textView.setSelectedRange(NSRange(location: editor.characterLocation(of: BlockPosition(block: 1, offset: 0)), length: 0))
        #expect(editor.paste(from: board))

        // Sofort da, Datei noch nicht gelesen: Platzhalter.
        #expect(kinds == [.paragraph, .image, .paragraph])
        let id = try #require(editor.document[1].assetID)
        #expect(editor.pendingImports.contains(id))
        #expect(EditorImageCache.shared.entry(for: id) == nil)

        try await waitUntil { EditorImageCache.shared.entry(for: id) != nil }
        #expect(editor.document[1].assetID == id)
        #expect(try await store.imageData(id) != nil)
    }

    @Test func undoDuringImportStaysUndone() async throws {
        editor.insertImages([.file(try pngFile())], from: BlockPosition(block: 1, offset: 0), to: BlockPosition(block: 1, offset: 0))
        let id = try #require(editor.document[1].assetID)
        undo()
        #expect(kinds == [.paragraph, .paragraph])

        try await waitUntil { editor.pendingImports.isEmpty }
        // Der fertige Import fügt nichts wieder ein …
        #expect(kinds == [.paragraph, .paragraph])
        // … und Redo bringt den Block mit demselben Bild zurück.
        editor.undoManager.redo()
        #expect(kinds == [.paragraph, .image, .paragraph])
        #expect(editor.document[1].assetID == id)
        try await waitUntil { EditorImageCache.shared.entry(for: id) != nil }
    }

    @Test func pastingImageOverSelectionIsOneUndoStep() async throws {
        editor.load(EditorDocument(blocks: [EditorBlock(text: "Hallo Welt"), EditorBlock(text: "Zweite Zeile")]))
        let start = editor.characterLocation(of: BlockPosition(block: 0, offset: 6))
        let end = editor.characterLocation(of: BlockPosition(block: 1, offset: 7))
        editor.textView.setSelectedRange(NSRange(location: start, length: end - start))

        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setData(Self.png(width: 20, height: 20), forType: .png)
        #expect(editor.paste(from: board))
        #expect(kinds == [.paragraph, .image, .paragraph])
        #expect(editor.document.blocks.map(\.text) == ["Hallo ", "", "Zeile"])
        try await waitUntil { editor.pendingImports.isEmpty }

        undo()
        #expect(editor.document.blocks.map(\.text) == ["Hallo Welt", "Zweite Zeile"])
        #expect(!kinds.contains(.image))
    }
}
#endif
