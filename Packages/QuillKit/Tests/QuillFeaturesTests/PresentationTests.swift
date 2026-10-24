import AppKit
import Foundation
import QuillDesign
import QuillEditorCore
@testable import QuillFeatures
import QuillModel
import Testing

/// Präsentieren (18.2, ADR-035): Folien an Überschriften, Blättern, Stand beim Start.
@Suite("Präsentieren")
struct PresentationTests {
    private func texts(_ slides: [[EditorBlock]]) -> [[String]] {
        slides.map { $0.map(\.text) }
    }

    @Test func topHeadingLevelSplitsAndTheTitleComesFirst() {
        let blocks = [
            EditorBlock(text: "Einleitung"),
            EditorBlock(kind: .heading1, text: "Ziele"),
            EditorBlock(kind: .heading2, text: "Kurzfristig"),
            EditorBlock(kind: .bulleted, text: "Mehr schlafen"),
            EditorBlock(kind: .heading1, text: "Plan"),
        ]
        let slides = SlideDeck.slides(title: "Woche", blocks: blocks)
        #expect(texts(slides) == [["Woche", "Einleitung"], ["Ziele", "Kurzfristig", "Mehr schlafen"], ["Plan"]])
        #expect(slides[0][0].kind == .heading1)
    }

    @Test func withoutHeading1TheNextLevelSplits() {
        let blocks = [
            EditorBlock(kind: .heading3, text: "Notiz"),
            EditorBlock(kind: .heading2, text: "Montag"),
            EditorBlock(kind: .heading3, text: "Früh"),
            EditorBlock(kind: .heading2, text: "Dienstag"),
        ]
        let slides = SlideDeck.slides(title: "Woche", blocks: blocks)
        #expect(texts(slides) == [["Woche", "Notiz"], ["Montag", "Früh"], ["Dienstag"]])
    }

    @Test func withoutHeadingsThePageIsOneSlide() {
        let slides = SlideDeck.slides(title: "Einkauf", blocks: [EditorBlock(text: "Milch"), EditorBlock(kind: .divider)])
        #expect(slides.count == 1)
        #expect(texts(SlideDeck.slides(title: "Leer", blocks: [])) == [["Leer"]])
    }

    @Test func magnificationFillsTheWidthWithinLimits() {
        let column = QuillDesign.Presentation.columnWidth
        #expect(PresentationModel.magnification(forWidth: column / 2) == 1)
        #expect(PresentationModel.magnification(forWidth: column * 2) == 2)
        #expect(PresentationModel.magnification(forWidth: column * 10) == QuillDesign.Presentation.maxMagnification)
    }

    @Test func keysTurnPagesAndEscapeCloses() {
        #expect(PresentationKeys.key(special: .rightArrow, characters: nil) == .next)
        #expect(PresentationKeys.key(special: .pageDown, characters: nil) == .next)
        #expect(PresentationKeys.key(special: .carriageReturn, characters: "\r") == .next)
        #expect(PresentationKeys.key(special: .upArrow, characters: nil) == .previous)
        #expect(PresentationKeys.key(special: nil, characters: " ") == .next)
        #expect(PresentationKeys.key(special: nil, characters: " ", modifiers: .shift) == .previous)
        #expect(PresentationKeys.key(special: .home, characters: nil) == .first)
        #expect(PresentationKeys.key(special: .end, characters: nil) == .last)
        #expect(PresentationKeys.key(special: nil, characters: "\u{1b}") == .close)
        #expect(PresentationKeys.key(special: nil, characters: "a") == nil)
        // ⌘←, ⌥↓, ⌃Leertaste gehören Menü und System.
        #expect(PresentationKeys.key(special: .leftArrow, characters: nil, modifiers: .command) == nil)
        #expect(PresentationKeys.key(special: .downArrow, characters: nil, modifiers: .option) == nil)
        #expect(PresentationKeys.key(special: nil, characters: " ", modifiers: .control) == nil)
    }

    @MainActor
    @Test func savesOpenChangesAndStopsAtTheEnds() async throws {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let page = try await store.createPage(title: "Vortrag")
        let bridge = EditorPersistenceBridge(pageID: page, store: store)
        _ = try await bridge.load()
        // Noch nicht gespeichert: Die Präsentation speichert vorher selbst.
        bridge.documentDidChange(EditorDocument(blocks: [
            EditorBlock(kind: .heading1, text: "Eins"),
            EditorBlock(kind: .heading1, text: "Zwei"),
        ]))
        let model = PresentationModel(pageID: page, store: store)
        await model.load(title: "Vortrag")
        #expect(model.phase == .ready)
        #expect(model.slides.count == 3)
        #expect(model.controller.document.blocks.map(\.text) == ["Vortrag"])
        #expect(!model.controller.allowsEditing)
        #expect(!model.controller.isSelectable)
        model.fit(width: QuillDesign.Presentation.columnWidth * 2)
        #expect(model.controller.scrollView.magnification == 2)

        model.previous()
        #expect(model.index == 0)
        model.last()
        #expect(model.controller.document.blocks.map(\.text) == ["Zwei"])
        model.next()
        #expect(model.index == 2)
        model.first()
        // Die nächste Folie beginnt oben, auch nach Scrollen auf der vorigen.
        model.controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 300))
        model.handle(.next)
        #expect(model.controller.document.blocks.map(\.text) == ["Eins"])
        #expect(model.controller.scrollView.contentView.bounds.origin.y == 0)
        model.handle(.close)
        #expect(model.index == 1)
        withExtendedLifetime(bridge) {}
    }
}
