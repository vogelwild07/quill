#if DEBUG
/// Nur für Tests der App (`-QuillFakeAI`, ADR-032): antwortet sofort und immer gleich,
/// damit UI-Tests weder Apple Intelligence brauchen noch von der Antwort des Modells abhängen.
public struct TestTextModel: TextModel {
    public init() {}

    public func respond(instructions: String, prompt: String) async throws -> String {
        let firstLine = prompt.split(separator: "\n", omittingEmptySubsequences: true).first ?? ""
        return "Antwort des Test-Modells: \(firstLine)"
    }
}
#endif
