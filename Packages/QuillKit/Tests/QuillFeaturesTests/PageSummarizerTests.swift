import Foundation
import QuillAI
@testable import QuillFeatures
import QuillModel
import Testing

/// Seite zusammenfassen (16.2, ADR-032) mit einem Modell, das mitschreibt.
@Suite("KI: Seite zusammenfassen")
struct PageSummarizerTests {
    /// Antwortet mit „Kurz <n>“ und merkt sich jede Anfrage.
    actor RecordingModel: TextModel {
        private(set) var prompts: [String] = []
        var answer: (@Sendable (Int) -> String) = { "Kurz \($0)" }

        func setAnswer(_ answer: @escaping @Sendable (Int) -> String) { self.answer = answer }

        func respond(instructions: String, prompt: String) async throws -> String {
            prompts.append(prompt)
            return answer(prompts.count)
        }

        func list(instructions: String, prompt: String) async throws -> [String] { [] }
    }

    static func block(_ text: String, _ kind: BlockKind = .paragraph) -> BlockSnapshot {
        BlockSnapshot(id: UUID(), kindRaw: kind.rawValue, text: text)
    }

    @Test func shortPageIsOneRequestWithoutImagesAndEmptyBlocks() async throws {
        let model = RecordingModel()
        let blocks = [Self.block("Einkauf", .heading1), Self.block(""), Self.block("\u{FFFC}", .image), Self.block("Milch\u{2028}Brot", .todo), Self.block("", .divider)]
        let summary = try await PageSummarizer(model: model).summarize(blocks)
        #expect(summary == "Kurz 1")
        #expect(await model.prompts == ["Einkauf\nMilch\nBrot"])
    }

    @Test func emptyPageAsksNothing() async throws {
        let model = RecordingModel()
        await #expect(throws: PageSummarizer.Failure.empty) {
            try await PageSummarizer(model: model).summarize([Self.block("  "), Self.block("", .image)])
        }
        #expect(await model.prompts.isEmpty)
    }

    @Test func longPageGoesInPartsAndThenTheParts() async throws {
        let model = RecordingModel()
        let paragraph = String(repeating: "a", count: 2500)
        let blocks = (0..<5).map { _ in Self.block(paragraph) }
        let summary = try await PageSummarizer(model: model).summarize(blocks)
        let prompts = await model.prompts
        // 5 × 2.500 Zeichen: drei Stücke (2, 2, 1 Absätze), dann ihre Zusammenfassungen.
        #expect(prompts.count == 4)
        #expect(prompts.dropLast().allSatisfy { $0.count <= PageSummarizer.chunkLimit })
        #expect(prompts.last == "Kurz 1\nKurz 2\nKurz 3")
        #expect(summary == "Kurz 4")
    }

    @Test func answersBecomeOneParagraph() async throws {
        let model = RecordingModel()
        await model.setAnswer { _ in "Erster Satz.\n\n  Zweiter Satz. \nDritter." }
        let summary = try await PageSummarizer(model: model).summarize([Self.block("Text")])
        #expect(summary == "Erster Satz. Zweiter Satz. Dritter.")
    }

    @Test func overlongLineIsSplitHard() {
        let chunks = PageSummarizer.chunks("kurz\n" + String(repeating: "b", count: 25) + "\nende", limit: 10)
        #expect(chunks == ["kurz", "bbbbbbbbbb", "bbbbbbbbbb", "bbbbb\nende"])
    }

    @Test func modelThatNeverGetsShorterStopsAfterThreeRounds() async throws {
        let model = RecordingModel()
        let long = String(repeating: "c", count: PageSummarizer.chunkLimit)
        await model.setAnswer { _ in long }
        _ = try await PageSummarizer(model: model).summarize([Self.block(long), Self.block(long)])
        // Runde 1: 2 Stücke; Runde 2: wieder 2; Runde 3: nur noch das erste.
        #expect(await model.prompts.count == 5)
    }
}
