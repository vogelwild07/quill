import Foundation
import Vision

/// Erkennt Text in Bilddaten, nur auf dem Gerät (17.1, ADR-034).
protocol TextRecognizer: Sendable {
    /// Erkannte Zeilen, durch Zeilenumbrüche getrennt; leer ohne Text.
    func text(in data: Data) async throws -> String
}

/// Vision: rechnet nur lokal und berührt keinen Zustand des Systems, darum auch für
/// Test-Stores.
struct VisionTextRecognizer: TextRecognizer {
    func text(in data: Data) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        return try await request.perform(on: data)
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
