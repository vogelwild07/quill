import Foundation
import QuillAI
@testable import QuillFeatures
import QuillModel
import Testing

/// Frag deine Notizen (16.4, ADR-032): Quellen aus der Suche, nur sie gehen ans Modell.
@Suite("KI: Frag deine Notizen")
struct NoteAnswererTests {
    /// Gibt feste Suchbegriffe zurück und merkt sich jede Frage an das Modell.
    actor RecordingModel: TextModel {
        let terms: [String]
        private(set) var prompts: [String] = []

        init(terms: [String]) { self.terms = terms }

        func respond(instructions: String, prompt: String) async throws -> String {
            prompts.append(prompt)
            return " Antwort \n"
        }

        func list(instructions: String, prompt: String) async throws -> [String] { terms }
    }

    static func store() throws -> PageStore {
        PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
    }

    @discardableResult
    static func page(_ title: String, _ texts: [String], in store: PageStore) async throws -> UUID {
        let id = try await store.createPage(title: title)
        let blocks = texts.map { BlockSnapshot(id: UUID(), text: $0) }
        try await store.applyEdits(id, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        return id
    }

    @Test func onlyPagesFromTheSearchGoToTheModel() async throws {
        let store = try Self.store()
        let shopping = try await Self.page("Einkauf", ["Milch kaufen", "Brot"], in: store)
        try await Self.page("Urlaub", ["Wir fahren an den See."], in: store)
        let trashed = try await Self.page("Alt", ["Milch war sauer"], in: store)
        try await store.trash(trashed)
        let model = RecordingModel(terms: ["Milch"])

        let answer = try await NoteAnswerer(model: model, store: store).answer("  Was soll ich kaufen? ")
        #expect(answer == NoteAnswerer.Answer(text: "Antwort", sources: [.init(pageID: shopping, title: "Einkauf")]))
        #expect(await model.prompts == ["Frage: Was soll ich kaufen?\n\nNotizen:\n\n[1] Einkauf\nMilch kaufen\nBrot"])
    }

    @Test func wordsOfTheQuestionWhenTheModelTermsFindNothing() async throws {
        let store = try Self.store()
        let trip = try await Self.page("Urlaub", ["Gardasee im Juni"], in: store)
        let model = RecordingModel(terms: ["Xylophon"])
        let answer = try await NoteAnswerer(model: model, store: store).answer("Wohin geht der Urlaub?")
        #expect(answer.sources.map(\.pageID) == [trip])
    }

    @Test func emptyQuestionAsksNothing() async throws {
        let model = RecordingModel(terms: ["Milch"])
        await #expect(throws: NoteAnswerer.Failure.emptyQuestion) {
            try await NoteAnswerer(model: model, store: try Self.store()).answer(" \n ")
        }
        #expect(await model.prompts.isEmpty)
    }

    @Test func withoutSourcesTheModelIsNotAsked() async throws {
        let store = try Self.store()
        try await Self.page("Einkauf", ["Milch kaufen"], in: store)
        let model = RecordingModel(terms: ["Xylophon"])
        await #expect(throws: NoteAnswerer.Failure.noSources) {
            try await NoteAnswerer(model: model, store: store).answer("Wo ist das Xylophon?")
        }
        #expect(await model.prompts.isEmpty)
    }

    @Test func pagesWithMoreTermsFirstAndAtMostFive() async throws {
        let store = try Self.store()
        // Zuerst angelegt: Die Suche zeigt sie unter „Milch“ zuletzt.
        let both = try await Self.page("Frühstück", ["Milch und Brot"], in: store)
        for index in 1...6 { try await Self.page("Liste \(index)", ["Milch"], in: store) }
        let model = RecordingModel(terms: ["Milch", "Brot"])
        let answer = try await NoteAnswerer(model: model, store: store).answer("Was gibt es zum Frühstück?")
        #expect(answer.sources.count == NoteAnswerer.maxSources)
        #expect(answer.sources.first?.pageID == both)
    }

    @Test func longPagesAreCutAroundTheHit() async throws {
        let store = try Self.store()
        let filler = String(repeating: "Füllwort ", count: 1500)
        try await Self.page("Haus", [filler, "Der Schlüssel liegt unter der Matte.", filler], in: store)
        try await Self.page("Garten", ["Schlüssel für den Schuppen"], in: store)
        let model = RecordingModel(terms: ["Schlüssel"])
        _ = try await NoteAnswerer(model: model, store: store).answer("Wo ist der Schlüssel?")
        let prompt = try #require(await model.prompts.first)
        #expect(prompt.contains("Der Schlüssel liegt unter der Matte."))
        #expect(prompt.contains("Schlüssel für den Schuppen"))
        #expect(prompt.count < NoteAnswerer.textLimit + 200)
    }

    @Test func termsWithoutEmptyDuplicatesAndPunctuation() {
        #expect(NoteAnswerer.cleanedTerms(["Milch.", " milch", "", "Brot", "Käse", "Äpfel", "Tee", "Saft"])
            == ["Milch", "Brot", "Käse", "Äpfel", "Tee"])
        #expect(NoteAnswerer.words(of: "Wann rufe ich Oma an?") == ["Wann", "rufe"])
    }
}
