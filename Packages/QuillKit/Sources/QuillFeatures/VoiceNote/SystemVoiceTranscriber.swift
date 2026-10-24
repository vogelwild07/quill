#if canImport(AppKit)
import AVFAudio
import Foundation
import Speech
import Synchronization

/// Abschrift aus dem Mikrofon des Macs mit `SpeechAnalyzer`, nur auf dem Gerät (ADR-034).
/// Nur für den echten Store. Quill lädt keine Modelle: Fehlt das für die Sprache des
/// Systems, beginnt keine Aufnahme.
struct SystemVoiceTranscriber: VoiceTranscriber {
    func start() async throws -> VoiceRecording {
        // Sprache zuerst: Ohne ihr Modell fragt Quill gar nicht erst nach dem Mikrofon.
        guard let locale = await Self.installedLocale() else { throw VoiceProblem.languageMissing }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoiceProblem.recognizerUnavailable
        }
        guard await Self.microphoneAllowed() else { throw VoiceProblem.microphoneDenied }
        let microphone = try Microphone(format: format)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            try await analyzer.start(inputSequence: microphone.inputs)
            try microphone.start()
        } catch {
            microphone.stop()
            await analyzer.cancelAndFinishNow()
            throw error
        }

        let (updates, continuation) = AsyncThrowingStream.makeStream(of: VoiceUpdate.self)
        let reader = Task {
            do {
                for try await result in transcriber.results {
                    continuation.yield(VoiceUpdate(text: String(result.text.characters), isFinal: result.isFinal))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        // Bei jedem Ende das Mikrofon freigeben; nach einem Abbruch oder Fehler auch die Erkennung.
        continuation.onTermination = { termination in
            microphone.stop()
            if case .finished(nil) = termination { return }
            reader.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
        return VoiceRecording(updates: updates, finish: {
            microphone.stop()
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        })
    }

    /// Fragt erst hier, beim ersten „Aufnehmen“.
    private static func microphoneAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .undetermined: await AVAudioApplication.requestRecordPermission()
        case .denied: false
        @unknown default: false
        }
    }

    /// Sprache des Systems, nur wenn ihr Modell schon installiert ist.
    private static func installedLocale() async -> Locale? {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else { return nil }
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) } ? locale : nil
    }
}

/// Mikrofon über `AVAudioEngine`, umgewandelt ins Format der Erkennung. Die Puffer gehen
/// direkt an die Erkennung und nie in eine Datei.
private final class Microphone: Sendable {
    let inputs: AsyncStream<AnalyzerInput>
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let engine: Mutex<AVAudioEngine?>

    init(format: AVAudioFormat) throws {
        (inputs, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw VoiceProblem.noMicrophone
        }
        let continuation = continuation
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            if let converted = Self.convert(buffer, with: converter, to: format) {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
        self.engine = Mutex(engine)
    }

    func start() throws {
        try engine.withLock { engine in
            engine?.prepare()
            try engine?.start()
        }
    }

    /// Mehrfach erlaubt; danach endet `inputs`.
    func stop() {
        engine.withLock { engine in
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            engine = nil
        }
        continuation.finish()
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard capacity > 0, let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var handedOver = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if handedOver {
                status.pointee = .noDataNow
                return nil
            }
            handedOver = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }
}
#endif
