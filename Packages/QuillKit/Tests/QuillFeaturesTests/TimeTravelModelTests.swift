#if DEBUG
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

    @Test func pageWithoutHistoryShowsNoDays() async throws {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let page = try await store.createPage(title: "Neu")
        let model = TimeTravelModel(pageID: page, store: store) {}
        await model.load()
        #expect(model.phase == .ready)
        #expect(model.days.isEmpty)
    }
}
#endif
