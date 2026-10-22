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
        // Je Anfrage eine neue Sitzung: Nichts aus früheren Anfragen fließt mit ein.
        let session = LanguageModelSession(model: .default, instructions: instructions)
        return try await session.respond(to: prompt).content
    }
}
