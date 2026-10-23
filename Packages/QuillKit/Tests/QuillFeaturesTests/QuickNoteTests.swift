import Foundation
@testable import QuillFeatures
import QuillModel
import Testing

/// Schnellnotiz (15.3, ADR-033): Schalter und Sichern als neue Seite.
@Suite("Schnellnotiz")
@MainActor
struct QuickNoteTests {
    let store: PageStore

    init() throws {
        store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
    }

    @Test func offByDefaultAndRememberedPerMac() throws {
        let suite = "QuickNoteTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let note = QuickNote(store: store, defaults: defaults)
        #expect(!note.isEnabled && !note.isShortcutEnabled && !note.wantsShortcut)
        note.setShortcutEnabled(true)
        #expect(!note.wantsShortcut, "Kürzel nur mit dem Symbol")
        note.setEnabled(true)
        #expect(note.wantsShortcut)

        let again = QuickNote(store: store, defaults: defaults)
        #expect(again.isEnabled && again.isShortcutEnabled)
    }

    @Test func testStoresForgetTheChoice() {
        let note = QuickNote(store: store, defaults: nil)
        note.setEnabled(true)
        #expect(note.isEnabled)
        #expect(!QuickNote(store: store, defaults: nil).isEnabled)
    }

    @Test func firstLineBecomesTheTitleAndTheRestParagraphs() async throws {
        let note = QuickNote(store: store, defaults: nil)
        note.draft = "\n  Anruf Werkstatt \nTermin Dienstag\n\n  Reifen mitnehmen"
        #expect(note.canSave)
        let id = try await note.save()

        #expect(try await store.activeTitles(of: [id]) == [id: "Anruf Werkstatt"])
        #expect(try await store.blocks(of: id).map(\.text) == ["Termin Dienstag", "Reifen mitnehmen"])
        #expect(note.draft.isEmpty)
        #expect(!note.canSave)
    }

    @Test func emptyDraftSavesNothing() async throws {
        let note = QuickNote(store: store, defaults: nil)
        note.draft = "  \n\t\n"
        #expect(!note.canSave)
        await #expect(throws: QuickNote.Failure.empty) { try await note.save() }
        #expect(try await store.recentPages().isEmpty)
        #expect(note.draft == "  \n\t\n")
    }

    @Test func takenShortcutIsReported() {
        let note = QuickNote(store: store, defaults: nil)
        note.reportShortcut(taken: true)
        #expect(note.isShortcutTaken)
        note.reportShortcut(taken: false)
        #expect(!note.isShortcutTaken)
    }
}
