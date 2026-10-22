#if DEBUG
import AppKit
import Foundation
import QuillEditorCore
@testable import QuillFeatures
import QuillModel
import QuillSync
import Testing

/// Zeitreise-Fenster ohne Oberfläche (12.3, ADR-031): Tage, gezeigter Stand, Zurückholen.
/// Store nur im Arbeitsspeicher, Geschichte aus `TimeTravelSeed`.
@MainActor
@Suite("Zeitreise: Fenster")
struct TimeTravelModelTests {
    private func seeded() async throws -> (PageStore, UUID, HistoryObserver) {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let page = try await TimeTravelSeed.write(to: store)
        let observer = HistoryObserver(recorder: HistoryRecorder(store: store))
        observer.start()
        return (store, page, observer)
    }

    @Test func showsDaysNewestFirstAndTheChosenState() async throws {
        let (store, page, observer) = try await seeded()
        let model = TimeTravelModel(pageID: page, store: store) { await observer.flush() }
        await model.load()
        #expect(model.phase == .ready)
        #expect(model.days.count == 3)
        #expect(model.days.map(\.day) == model.days.map(\.day).sorted(by: >))
        // Neuester Tag gewählt: heute nur „Erster Absatz“.
        #expect(model.controller.document.blocks.map(\.text) == ["Erster Absatz"])
        model.selectedDay = model.days[2]
        #expect(model.controller.document.blocks.map(\.text) == ["Erster Absatz", "Alter Absatz"])
        #expect(model.controller.isReadOnly)
        #expect(model.canRestore == false)
    }

    @Test func restoringBringsTheParagraphBackAndIntoTodaysHistory() async throws {
        let (store, page, observer) = try await seeded()
        let model = TimeTravelModel(pageID: page, store: store) { await observer.flush() }
        await model.load()
        model.selectedDay = model.days[2]
        let old = try #require(model.controller.document.blocks.last)
        await model.restore([old.id])
        #expect(model.restoreFailed == false)
        #expect(try await store.blocks(of: page).map(\.text) == ["Erster Absatz", "Alter Absatz"])
        // Der gewählte Tag bleibt gewählt; „Heute“ enthält jetzt die Rückholung.
        #expect(model.selectedDay == model.days[2])
        model.selectedDay = model.days[0]
        #expect(model.controller.document.blocks.map(\.text) == ["Erster Absatz", "Alter Absatz"])
    }

    @Test func markedTextEnablesRestoringOnlyTheMarkedParagraphs() async throws {
        let (store, page, observer) = try await seeded()
        let model = TimeTravelModel(pageID: page, store: store) { await observer.flush() }
        await model.load()
        model.selectedDay = model.days[2]
        let old = try #require(model.controller.document.blocks.last)
        model.controller.reveal(blockID: old.id, range: NSRange(location: 0, length: 3))
        #expect(model.canRestore)
        await model.restoreSelection()
        #expect(try await store.blocks(of: page).map(\.text) == ["Erster Absatz", "Alter Absatz"])
        // Der frühere Tag ändert sich dabei nicht; die Markierung bleibt stehen.
        #expect(model.canRestore)
        model.selectedDay = model.days[0]
        #expect(model.canRestore == false)
    }

    /// Ein Bild-Block kommt nur mit Bild zurück (Frist, 12.4); sonst ein Hinweis.
    @Test func imageBlocksComeBackOnlyWithTheirImage() async throws {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let kept = try await store.importImage(Self.png())
        let first = BlockSnapshot(id: UUID(), text: "Erster Absatz")
        let keptBlock = BlockSnapshot(id: UUID(), kindRaw: BlockKind.image.rawValue, properties: BlockProperties(assetID: kept.assetID))
        let goneBlock = BlockSnapshot(id: UUID(), kindRaw: BlockKind.image.rawValue, properties: BlockProperties(assetID: UUID()))
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let document = try PageHistory.testDocument([(yesterday, [first, keptBlock, goneBlock]), (.now, [first])])
        let page = try await store.createPage(title: "Bilder")
        try await store.applyEdits(page, BlockEdits(upserts: [first], order: [first.id]))
        _ = try await store.saveHistory(page, document: document)

        let model = TimeTravelModel(pageID: page, store: store) {}
        await model.load()
        model.selectedDay = model.days[1]
        await model.restore([goneBlock.id])
        #expect(model.skippedImages == 1)
        #expect(try await store.blocks(of: page).map(\.id) == [first.id])

        await model.restore([keptBlock.id, goneBlock.id])
        #expect(model.skippedImages == 1)
        #expect(try await store.blocks(of: page).map(\.id) == [first.id, keptBlock.id])
        #expect(try await store.imageData(kept.assetID) != nil)
    }

    @Test func pageWithoutHistoryShowsNoDays() async throws {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let page = try await store.createPage(title: "Neu")
        let model = TimeTravelModel(pageID: page, store: store) {}
        await model.load()
        #expect(model.phase == .ready)
        #expect(model.days.isEmpty)
    }

    private static func png() -> Data {
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    }
}
#endif
