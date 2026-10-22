import Foundation
import QuillAI
import QuillModel

/// Fasst eine Seite mit dem Modell auf dem Gerät zusammen (16.2, ADR-032). Lange Seiten
/// gehen in Stücken an das Modell; die Teilergebnisse werden dann noch einmal
/// zusammengefasst.
struct PageSummarizer {
    /// Zeichen je Anfrage: Das Modell fasst rund 4.000 Token für Anweisung, Text und
    /// Antwort zusammen; deutscher Text braucht etwa ein Token für drei bis vier Zeichen.
    static let chunkLimit = 6000
    /// Runden des Zusammenfassens, danach wird gekürzt (das Modell antwortet zu lang).
    static let maxRounds = 3

    static let instructions = """
        Du fasst Notizen zusammen. Antworte in der Sprache der Notiz, in höchstens fünf Sätzen, \
        als ein einziger Absatz ohne Überschrift und ohne Aufzählung. Gib nur wieder, was in der \
        Notiz steht, und erfinde nichts dazu.
        """

    enum Failure: Error, Equatable {
        /// Die Seite hat keinen Text.
        case empty
    }

    let model: any TextModel

    func summarize(_ blocks: [BlockSnapshot]) async throws -> String {
        let text = Self.plainText(blocks)
        guard !text.isEmpty else { throw Failure.empty }
        return try await summarize(text, round: 1)
    }

    private func summarize(_ text: String, round: Int) async throws -> String {
        let parts = Self.chunks(text, limit: Self.chunkLimit)
        if parts.count == 1 { return try await respond(parts[0]) }
        guard round < Self.maxRounds else { return try await respond(parts[0]) }
        var summaries: [String] = []
        for part in parts {
            try Task.checkCancellation()
            summaries.append(try await respond(part))
        }
        return try await summarize(summaries.joined(separator: "\n"), round: round + 1)
    }

    private func respond(_ text: String) async throws -> String {
        let answer = try await model.respond(instructions: Self.instructions, prompt: text)
        return Self.oneParagraph(answer)
    }

    /// Text der Seite, ein Absatz je Block; Bilder, Trenner und leere Blöcke fallen weg.
    static func plainText(_ blocks: [BlockSnapshot]) -> String {
        blocks.compactMap { block -> String? in
            switch BlockKind(rawValue: block.kindRaw) {
            case .image, .divider:
                return nil
            case .paragraph, .heading1, .heading2, .heading3, .bulleted, .numbered, .todo, .quote, .code, nil:
                let text = block.text.replacingOccurrences(of: "\u{2028}", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
        }
        .joined(separator: "\n")
    }

    /// Teilt an Zeilenenden in Stücke bis `limit` Zeichen; eine längere Zeile wird hart geteilt.
    static func chunks(_ text: String, limit: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = Substring(line)
            while line.count > limit {
                if !current.isEmpty { chunks.append(current); current = "" }
                chunks.append(String(line.prefix(limit)))
                line = line.dropFirst(limit)
            }
            if !current.isEmpty, current.count + 1 + line.count > limit {
                chunks.append(current)
                current = ""
            }
            current += current.isEmpty ? String(line) : "\n" + line
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Ein Absatz: Die Zusammenfassung wird wie getippt eingefügt, ein Zeilenende
    /// begänne dort einen neuen Block.
    static func oneParagraph(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
