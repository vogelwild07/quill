import Foundation
@testable import QuillFeatures
import QuillModel
import Testing

/// Sprachnotiz (17.2, ADR-034): Abschrift, Fehler, Ersatz für Test-Stores.
@Suite("Sprachnotiz")
@MainActor
struct VoiceNoteTests {
    @Test func memoryTranscriberEndsWithFinish() async throws {
        let recording = try MemoryVoiceTranscriber(text: "Milch und Brot").start()
        await recording.finish()
        var updates: [VoiceUpdate] = []
        for try await update in recording.updates { updates.append(update) }
        #expect(updates == [
            VoiceUpdate(text: "Milch", isFinal: false),
            VoiceUpdate(text: "Milch und", isFinal: false),
            VoiceUpdate(text: "Milch und Brot", isFinal: true),
        ])
    }

    @Test func pendingWordsAreReplacedFinalOnesKept() {
        let model = VoiceNoteModel(transcriber: MemoryVoiceTranscriber())
        model.apply(VoiceUpdate(text: "Milch", isFinal: false))
        model.apply(VoiceUpdate(text: "Milch und Brot", isFinal: false))
        #expect(model.finished.isEmpty)
        #expect(model.text == "Milch und Brot")
        model.apply(VoiceUpdate(text: "Milch und Brot kaufen.", isFinal: true))
        model.apply(VoiceUpdate(text: " Danach", isFinal: false))
        #expect(model.finished == "Milch und Brot kaufen.")
        #expect(model.pending == " Danach")
        #expect(model.text == "Milch und Brot kaufen. Danach")
    }

    @Test func stopKeepsTheTextAndASecondRecordingAppends() async throws {
        let model = VoiceNoteModel(transcriber: MemoryVoiceTranscriber(text: "Milch und Brot kaufen."))
        model.record()
        #expect(model.isRecording)
        try await waitUntil { model.phase == .recording && model.text == "Milch und Brot kaufen." }
        model.stop()
        await model.settle()
        #expect(model.phase == .ready)
        #expect(!model.isRecording)
        #expect(model.text == "Milch und Brot kaufen.")

        model.record()
        try await waitUntil { model.phase == .recording }
        model.stop()
        await model.settle()
        #expect(model.text == "Milch und Brot kaufen. Milch und Brot kaufen.")
    }

    @Test func pendingWordsStayWhenTheRecordingEnds() async throws {
        let model = VoiceNoteModel(transcriber: PendingOnly())
        model.record()
        try await waitUntil { model.phase == .recording && !model.pending.isEmpty }
        model.stop()
        await model.settle()
        #expect(model.finished == "Zahnarzt anrufen")
        #expect(model.pending.isEmpty)
    }

    @Test(arguments: [
        (VoiceProblem.microphoneDenied, "› Microphone”"),
        (VoiceProblem.languageMissing, "isn’t installed"),
        (VoiceProblem.noMicrophone, "No microphone"),
        (VoiceProblem.recognizerUnavailable, "isn’t available"),
    ])
    func problemsSaySo(problem: VoiceProblem, fragment: String) async {
        let model = VoiceNoteModel(transcriber: MemoryVoiceTranscriber(problem: problem))
        model.record()
        await model.settle()
        guard case .failed(let message) = model.phase else {
            Issue.record("Kein Fehler für \(problem)")
            return
        }
        #expect(message.contains(fragment), "\(message)")
        #expect(!model.isRecording)
    }

    @Test func cancelEndsTheRecording() async throws {
        let model = VoiceNoteModel(transcriber: MemoryVoiceTranscriber(text: "Milch"))
        model.record()
        try await waitUntil { model.phase == .recording }
        model.cancel()
        // Endet ohne „Stopp“; sonst hinge der Test hier.
        await model.settle()
    }

    @Test func testStoresNeverRecord() throws {
        let persistence = QuillPersistence(container: try QuillStore.makeInMemoryContainer(), backup: nil)
        #expect(persistence.isTestStore)
        let voice = try #require(persistence.voice as? MemoryVoiceTranscriber)
        #if DEBUG
        #expect(voice.words.joined(separator: " ") == MemoryVoiceTranscriber.sampleText)
        #else
        #expect(voice.words.isEmpty)
        #endif
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

/// Nur unsichere Wörter, nie ein fester Abschnitt.
private struct PendingOnly: VoiceTranscriber {
    func start() -> VoiceRecording {
        let (updates, continuation) = AsyncThrowingStream.makeStream(of: VoiceUpdate.self)
        continuation.yield(VoiceUpdate(text: "Zahnarzt anrufen", isFinal: false))
        return VoiceRecording(updates: updates, finish: { continuation.finish() })
    }
}
