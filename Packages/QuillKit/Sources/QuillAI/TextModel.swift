import Foundation

/// Sprachmodell hinter den KI-Funktionen (ADR-032). In der App das Modell auf dem Gerät
/// (`OnDeviceModel`), in Tests eines mit festen Antworten.
public protocol TextModel: Sendable {
    /// Antwort auf `prompt`; `instructions` sagt dem Modell, was es tun soll.
    func respond(instructions: String, prompt: String) async throws -> String
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
