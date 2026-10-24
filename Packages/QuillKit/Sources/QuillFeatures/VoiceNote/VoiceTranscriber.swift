import Foundation

/// Ein Stand der Abschrift: unsichere Wörter ersetzt der nächste Stand, feste bleiben (17.2, ADR-034).
struct VoiceUpdate: Equatable, Sendable {
    let text: String
    let isFinal: Bool
}

/// Warum keine Aufnahme beginnt.
enum VoiceProblem: Error, Equatable {
    /// Quill darf das Mikrofon nicht nutzen.
    case microphoneDenied
    /// Das Modell für die Sprache des Systems ist auf diesem Mac nicht installiert.
    case languageMissing
    /// Kein Mikrofon angeschlossen.
    case noMicrophone
    /// Die Erkennung bietet kein Audioformat an.
    case recognizerUnavailable
}

/// Eine laufende Aufnahme. `updates` endet nach `finish()` mit dem letzten festen Text;
/// bricht die lesende Aufgabe ab, endet die Aufnahme sofort, ohne Rest.
struct VoiceRecording: Sendable {
    let updates: AsyncThrowingStream<VoiceUpdate, any Error>
    let finish: @Sendable () async -> Void
}

/// Abschrift aus dem Mikrofon oder ein Ersatz für Test-Stores und Tests.
protocol VoiceTranscriber: Sendable {
    /// Fragt beim ersten Mal nach dem Mikrofon und beginnt die Aufnahme.
    func start() async throws -> VoiceRecording
}

/// Ersatz im Speicher: Test-Stores nehmen nie über das Mikrofon auf, denn Debug-Builds
/// haben dieselbe Kennung wie die echte App.
struct MemoryVoiceTranscriber: VoiceTranscriber {
    /// Wörter der Abschrift; erst einzeln unsicher, dann zusammen fest.
    let words: [String]
    let problem: VoiceProblem?

    init(text: String = "", problem: VoiceProblem? = nil) {
        words = text.split(separator: " ").map(String.init)
        self.problem = problem
    }

    #if DEBUG || QUILL_SYNCTEST
    /// Fester Text für Test-Stores (UI-Tests), nur im Debug-Build.
    static let sampleText = "Milch und Brot kaufen."
    #endif

    func start() throws -> VoiceRecording {
        if let problem { throw problem }
        let (updates, continuation) = AsyncThrowingStream.makeStream(of: VoiceUpdate.self)
        for count in words.indices.dropLast() {
            continuation.yield(VoiceUpdate(text: words[...count].joined(separator: " "), isFinal: false))
        }
        if !words.isEmpty {
            continuation.yield(VoiceUpdate(text: words.joined(separator: " "), isFinal: true))
        }
        return VoiceRecording(updates: updates, finish: { continuation.finish() })
    }
}
