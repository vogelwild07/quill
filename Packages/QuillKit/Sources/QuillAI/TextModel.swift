import Foundation

/// Sprachmodell hinter den KI-Funktionen (ADR-032). In der App das Modell auf dem Gerät
/// (`OnDeviceModel`), in Tests eines mit festen Antworten.
public protocol TextModel: Sendable {
    /// Antwort auf `prompt`; `instructions` sagt dem Modell, was es tun soll. Wirft
    /// `AIError` oder `CancellationError`.
    func respond(instructions: String, prompt: String) async throws -> String
}

/// Warum das Modell nicht geantwortet hat, ohne Typen aus FoundationModels.
public enum AIError: Error, Equatable, Sendable {
    /// Der Text passt nicht in eine Anfrage.
    case tooLong
    /// Das Modell lehnt den Inhalt ab (Schutzregeln von Apple).
    case refused
    /// Sprache des Textes oder des Macs wird nicht unterstützt.
    case unsupportedLanguage
    /// Das Modell steht nicht mehr bereit.
    case unavailable
    /// Anderer Fehler.
    case failed
}

/// Ob das Modell auf dem Gerät bereitsteht, und wenn nicht, warum.
public enum AIAvailability: String, CaseIterable, Sendable {
    case available
    /// Der Mac kann Apple Intelligence nicht ausführen.
    case deviceNotEligible
    /// Apple Intelligence ist in den Systemeinstellungen aus.
    case appleIntelligenceNotEnabled
    /// Das Modell wird noch geladen oder vorbereitet.
    case modelNotReady
    /// Ein Grund, den diese Version von Quill noch nicht kennt.
    case unavailable
}
