import CoreGraphics
import Foundation
import ImageIO
@testable import QuillFeatures
import QuillModel
import Testing
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

/// Text in Bildern (17.1, ADR-034): Index im Speicher, Treffer der Suche, echte Erkennung.
@Suite("Text in Bildern")
@MainActor
struct ImageTextTests {
    let store: PageStore
    let recognizer: TableRecognizer

    init() throws {
        store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        recognizer = TableRecognizer()
    }

    /// Seite mit einem Bild-Block je Bild; liefert Seite, Blöcke und Assets.
    func page(_ title: String, images: [Data]) async throws -> (page: UUID, blocks: [UUID], assets: [UUID]) {
        let id = try await store.createPage(title: title)
        var blocks: [BlockSnapshot] = []
        var assets: [UUID] = []
        for data in images {
            let imported = try await store.importImage(data)
            assets.append(imported.assetID)
            blocks.append(BlockSnapshot(
                id: UUID(), kindRaw: BlockKind.image.rawValue, text: "\u{FFFC}", properties: BlockProperties(assetID: imported.assetID)
            ))
        }
        try await store.applyEdits(id, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        return (id, blocks.map(\.id), assets)
    }

    func index(delay: Duration = .milliseconds(10)) -> ImageTextIndex {
        ImageTextIndex(store: store, recognizer: recognizer, delay: delay)
    }

    @Test func recognizesEachImageOnceAndFindsItsText() async throws {
        let receipt = try Self.png(red: 0.1)
        let photo = try Self.png(red: 0.9)
        await recognizer.set(receipt, "Rechnung\nGärtnerei Müller")
        await recognizer.set(photo, "")
        let (_, _, assets) = try await page("Belege", images: [receipt, photo])
        let index = index()
        index.start()
        await index.settle()

        #expect(index.texts == [assets[0]: "Rechnung\nGärtnerei Müller", assets[1]: ""])
        #expect(index.excerpts(matching: "gartnerei") == [assets[0]: "Rechnung Gärtnerei Müller"])
        #expect(index.excerpts(matching: " ").isEmpty)

        // Eine weitere Speicherung erkennt nichts neu.
        _ = try await store.createPage(title: "Andere")
        try await Task.sleep(for: .milliseconds(50))
        await index.settle()
        #expect(await recognizer.calls == 2)
    }

    @Test func newImagesAfterStartAndTrashedPagesDrop() async throws {
        let first = try Self.png(red: 0.2)
        let second = try Self.png(red: 0.4)
        await recognizer.set(first, "Erstes")
        await recognizer.set(second, "Zweites")
        let index = index()
        index.start()
        await index.settle()
        #expect(index.texts.isEmpty)

        let (pageID, _, assets) = try await page("Neu", images: [first])
        try await waitFor { await index.settle(); return index.texts[assets[0]] == "Erstes" }

        let (other, _, otherAssets) = try await page("Noch eins", images: [second])
        try await waitFor { await index.settle(); return index.texts[otherAssets[0]] == "Zweites" }
        try await store.trash(pageID)
        try await waitFor { await index.settle(); return index.texts[assets[0]] == nil }
        #expect(index.texts.keys.sorted() == [otherAssets[0]])
        _ = other
    }

    @Test func unreadableImagesCountAsWithoutText() async throws {
        let image = try Self.png(red: 0.6)
        let (_, _, assets) = try await page("Kaputt", images: [image])
        let index = index()
        index.start()
        await index.settle()
        #expect(index.texts == [assets[0]: ""])
    }

    @Test func searchHitsPointToTheImageBlock() async throws {
        let image = try Self.png(red: 0.3)
        let (pageID, blocks, assets) = try await page("Ausflug", images: [image])
        let trashed = try await page("Alt", images: [try Self.png(red: 0.7)])
        try await store.trash(trashed.page)

        let hits = try await store.imageHits([assets[0]: "Fahrplan", trashed.assets[0]: "Fahrplan"], limit: 10)
        #expect(hits.map(\.kind) == [.image(blockID: blocks[0])])
        #expect(hits.first?.pageID == pageID)
        #expect(hits.first?.title == "Ausflug")
        #expect(hits.first?.excerpt == "Fahrplan")
        #expect(try await store.imageHits([assets[0]: "Fahrplan"], limit: 0).isEmpty)
        let images = try await store.activeImages()
        #expect(images.map(\.blockID) == [blocks[0]])
        #expect(images.map(\.pageID) == [pageID])
        #expect(images.map(\.assetID) == [assets[0]])
    }

    @Test func quickOpenListsImagesUnderContent() async throws {
        let image = try Self.png(red: 0.5)
        await recognizer.set(image, "Speisekarte Pizza")
        let (pageID, blocks, _) = try await page("Urlaub", images: [image])
        let index = index()
        index.start()
        await index.settle()

        let model = QuickOpenModel()
        model.query = "pizza"
        await model.load(from: store, imageText: index, debounce: .zero)
        #expect(model.sections.map(\.kind) == [.content])
        #expect(model.sections.first?.hits.map(\.kind) == [.image(blockID: blocks[0])])
        #expect(model.sections.first?.hits.first?.pageID == pageID)
    }

    #if canImport(AppKit)
    /// Echte Erkennung mit Vision auf einem gezeichneten Bild.
    @Test func visionReadsRenderedText() async throws {
        let text = try await VisionTextRecognizer().text(in: Self.rendered("Rechnung Gärtnerei"))
        #expect(text.contains("Rechnung"))
        #expect(text.contains("Gärtnerei"))
    }

    static func rendered(_ text: String) throws -> Data {
        let image = NSImage(size: NSSize(width: 600, height: 160), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            (text as NSString).draw(at: NSPoint(x: 20, y: 60), withAttributes: [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black])
            return true
        }
        let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        return try #require(rep.representation(using: .png, properties: [:]))
    }
    #endif

    func waitFor(_ condition: () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await condition(), sourceLocation: sourceLocation)
    }

    /// Einfarbiges PNG; verschiedene Farben ergeben verschiedene Daten.
    static func png(red: CGFloat) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: red, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

/// Ersatz für Vision: Text je Bilddaten; unbekannte Bilder kann er nicht lesen.
actor TableRecognizer: TextRecognizer {
    private var table: [Data: String] = [:]
    private(set) var calls = 0

    struct Unreadable: Error {}

    func set(_ data: Data, _ text: String) {
        table[data] = text
    }

    func text(in data: Data) throws -> String {
        calls += 1
        guard let text = table[data] else { throw Unreadable() }
        return text
    }
}
