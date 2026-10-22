import Foundation
import QuillAI
@testable import QuillFeatures
import QuillModel
import Testing

/// To-dos aus markierten Absätzen (16.3, ADR-032) mit einem Modell, das mitschreibt.
@Suite("KI: To-dos vorschlagen")
struct TodoSuggesterTests {
    /// Gibt je Anfrage die Liste aus `answer` zurück und merkt sich die Anfragen.
    actor RecordingModel: TextModel {
        private(set) var prompts: [String] = []
        private let answer: @Sendable (String) -> [String]

        init(answer: @escaping @Sendable (String) -> [String]) { self.answer = answer }

        func respond(instructions: String, prompt: String) async throws -> String { "" }

        func list(instructions: String, prompt: String) async throws -> [String] {
            prompts.append(prompt)
            return answer(prompt)
        }
    }

    @Test func selectionIsOneRequestWithoutImagesAndDividers() async throws {
        let model = RecordingModel { _ in ["Milch kaufen"] }
        let blocks: [(kind: BlockKind?, text: String)] = [
            (.paragraph, "Morgen Milch kaufen."), (.image, "\u{FFFC}"), (.divider, ""), (.bulleted, "Oma\u{2028}anrufen"),
        ]
        #expect(try await TodoSuggester(model: model).suggest(blocks) == ["Milch kaufen"])
        #expect(await model.prompts == ["Morgen Milch kaufen.\nOma\nanrufen"])
    }

    @Test func emptySelectionAsksNothing() async throws {
        let model = RecordingModel { _ in ["Nie"] }
        await #expect(throws: TodoSuggester.Failure.empty) {
            try await TodoSuggester(model: model).suggest([(.paragraph, "  "), (.image, "")])
        }
        #expect(await model.prompts.isEmpty)
    }

    @Test func noTasksIsExplained() async throws {
        let model = RecordingModel { _ in ["", " - "] }
        await #expect(throws: TodoSuggester.Failure.noTasks) {
            try await TodoSuggester(model: model).suggest([(.paragraph, "Schönes Wetter heute.")])
        }
    }

    @Test func longSelectionGoesInPartsAndTheListsAreJoined() async throws {
        let line = String(repeating: "a", count: 4000)
        let model = RecordingModel { prompt in ["Aufgabe \(prompt.count)"] }
        let items = try await TodoSuggester(model: model).suggest([(.paragraph, line), (.paragraph, line)])
        #expect(await model.prompts.count == 2)
        #expect(items == ["Aufgabe 4000"], "doppelte Einträge nur einmal")
    }

    @Test func markersNumbersAndBoxesAreRemoved() {
        let items = TodoSuggester.cleaned([
            "- Milch kaufen", "• Brot", "2. Oma anrufen", "3) Rechnung zahlen", "- [ ] Garten", "[x] Auto",
            "Milch kaufen", "Zwei\nZeilen", "  ", "-Bindestrich ohne Abstand",
        ])
        #expect(items == ["Milch kaufen", "Brot", "Oma anrufen", "Rechnung zahlen", "Garten", "Auto", "Zwei Zeilen", "-Bindestrich ohne Abstand"])
    }

    @Test func atMostFiftySuggestions() {
        let items = TodoSuggester.cleaned((1...80).map { "Aufgabe \($0)" })
        #expect(items.count == TodoSuggester.maxItems)
        #expect(items.last == "Aufgabe 50")
    }
}
