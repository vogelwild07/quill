import Foundation
import OSLog

/// Aufnahme und Abschrift im Blatt „Sprachnotiz“ (17.2, ADR-034). Die Aufnahme selbst
/// bleibt nirgends; übrig ist nur der Text.
@MainActor
@Observable
final class VoiceNoteModel {
    enum Phase: Equatable {
        case ready
        case starting
        case recording
        case finishing
        case failed(String)
    }

    private(set) var phase = Phase.ready
    /// Feste Abschnitte der Abschrift.
    private(set) var finished = ""
    /// Noch unsichere Wörter hinter `finished`.
    private(set) var pending = ""
    @ObservationIgnored private let transcriber: any VoiceTranscriber
    @ObservationIgnored private var recording: VoiceRecording?
    @ObservationIgnored private var task: Task<Void, Never>?

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "voice")

    init(transcriber: any VoiceTranscriber) {
        self.transcriber = transcriber
    }

    /// Was „Einfügen“ setzt; unsichere Wörter zählen mit.
    var text: String {
        Self.joined(finished, pending)
    }

    var isRecording: Bool {
        phase == .starting || phase == .recording || phase == .finishing
    }

    /// Nimmt auf; eine zweite Aufnahme hängt an den Text an.
    func record() {
        guard !isRecording else { return }
        phase = .starting
        task = Task { await run() }
    }

    /// Beendet die Aufnahme; die Erkennung liefert den Rest noch nach.
    func stop() {
        guard phase == .recording, let recording else { return }
        phase = .finishing
        Task { await recording.finish() }
    }

    /// Verwirft die laufende Aufnahme (Blatt geschlossen).
    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Bis die Aufnahme zu Ende ist (nur für Tests).
    func settle() async {
        await task?.value
    }

    private func run() async {
        do {
            let recording = try await transcriber.start()
            self.recording = recording
            phase = .recording
            for try await update in recording.updates {
                apply(update)
            }
            // Unsichere Wörter am Ende bleiben stehen: Sie sind das Letzte, was gesagt wurde.
            finished = text
            pending = ""
            if !Task.isCancelled { phase = .ready }
        } catch is CancellationError {
            // Blatt geschlossen.
        } catch {
            Self.logger.error("Sprachnotiz gescheitert: \(String(describing: error), privacy: .public)")
            pending = ""
            phase = .failed(Self.message(error))
        }
        recording = nil
    }

    func apply(_ update: VoiceUpdate) {
        if update.isFinal {
            finished = Self.joined(finished, update.text)
            pending = ""
        } else {
            pending = update.text
        }
    }

    private static func joined(_ first: String, _ second: String) -> String {
        [first, second]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func message(_ error: any Error) -> String {
        switch error {
        case VoiceProblem.microphoneDenied:
            String(localized: "Quill darf das Mikrofon nicht nutzen. Du kannst das in den Systemeinstellungen unter „Datenschutz & Sicherheit › Mikrofon“ ändern.", bundle: .module)
        case VoiceProblem.languageMissing:
            String(localized: "Die Spracherkennung für deine Sprache ist auf diesem Mac nicht installiert.", bundle: .module)
        case VoiceProblem.noMicrophone:
            String(localized: "Es ist kein Mikrofon angeschlossen.", bundle: .module)
        case VoiceProblem.recognizerUnavailable:
            String(localized: "Die Spracherkennung ist auf diesem Mac gerade nicht verfügbar.", bundle: .module)
        default:
            String(localized: "Die Aufnahme ist gescheitert.", bundle: .module)
        }
    }
}
