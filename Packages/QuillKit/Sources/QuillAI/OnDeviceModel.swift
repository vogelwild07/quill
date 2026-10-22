import FoundationModels

/// Das Sprachmodell von Apple Intelligence auf diesem Mac (ADR-032). Nur
/// `SystemLanguageModel`: Es rechnet auf dem Gerät, nichts geht ins Netz.
public struct OnDeviceModel: TextModel {
    public init() {}

    public static var availability: AIAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: .deviceNotEligible
            case .appleIntelligenceNotEnabled: .appleIntelligenceNotEnabled
            case .modelNotReady: .modelNotReady
            @unknown default: .unavailable
            }
        @unknown default:
            .unavailable
        }
    }

    public func respond(instructions: String, prompt: String) async throws -> String {
        try await run(instructions) { try await $0.respond(to: prompt).content }
    }

    public func list(instructions: String, prompt: String) async throws -> [String] {
        // Geführte Ausgabe: Das Modell füllt die Liste, statt Zeilen frei zu formatieren.
        try await run(instructions) { try await $0.respond(to: prompt, generating: ItemList.self).content.items }
    }

    @Generable
    struct ItemList {
        @Guide(description: "Die gefundenen Einträge, je einer kurz und ohne Aufzählungszeichen; leer, wenn es keine gibt")
        var items: [String]
    }

    private func run<Value>(
        _ instructions: String, _ request: (LanguageModelSession) async throws -> Value
    ) async throws -> Value {
        // Je Anfrage eine neue Sitzung: Nichts aus früheren Anfragen fließt mit ein.
        let session = LanguageModelSession(model: .default, instructions: instructions)
        do {
            return try await request(session)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.aiError(error)
        }
    }

    /// Ab macOS 27 wirft das Modell `LanguageModelError`, davor `GenerationError`.
    static func aiError(_ error: any Error) -> AIError {
        if #available(macOS 27.0, iOS 27.0, *), let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: return .tooLong
            case .guardrailViolation, .refusal: return .refused
            case .unsupportedLanguageOrLocale: return .unsupportedLanguage
            default: return .failed
            }
        }
        guard let error = error as? LanguageModelSession.GenerationError else { return .failed }
        switch error {
        case .exceededContextWindowSize: return .tooLong
        case .guardrailViolation, .refusal: return .refused
        case .unsupportedLanguageOrLocale: return .unsupportedLanguage
        case .assetsUnavailable: return .unavailable
        default: return .failed
        }
    }
}
