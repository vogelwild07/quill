import Foundation

/// Eintrag im Slash-Menü.
public struct SlashCommand: Identifiable, Equatable, Sendable {
    public var id: BlockKind { kind }
    public let kind: BlockKind
    public let title: String
    public let symbol: String
    public let shortcut: String?
    let aliases: [String]

    /// Alle Befehle in Menü-Reihenfolge.
    public static let all: [SlashCommand] = [
        .init(kind: .paragraph, title: "Text", symbol: "text.alignleft", shortcut: nil, aliases: ["text", "absatz", "paragraph"]),
        .init(kind: .heading1, title: "Überschrift 1", symbol: "textformat.size.larger", shortcut: "#", aliases: ["h1", "heading", "titel"]),
        .init(kind: .heading2, title: "Überschrift 2", symbol: "textformat.size", shortcut: "##", aliases: ["h2", "heading"]),
        .init(kind: .heading3, title: "Überschrift 3", symbol: "textformat.size.smaller", shortcut: "###", aliases: ["h3", "heading"]),
        .init(kind: .bulleted, title: "Aufzählung", symbol: "list.bullet", shortcut: "-", aliases: ["liste", "bullet", "ul"]),
        .init(kind: .numbered, title: "Nummerierte Liste", symbol: "list.number", shortcut: "1.", aliases: ["liste", "numbered", "ol"]),
        .init(kind: .todo, title: "To-do", symbol: "checklist", shortcut: "[]", aliases: ["aufgabe", "checkbox", "todo", "task"]),
        .init(kind: .quote, title: "Zitat", symbol: "text.quote", shortcut: ">", aliases: ["quote", "blockquote"]),
        .init(kind: .code, title: "Code", symbol: "chevron.left.forwardslash.chevron.right", shortcut: "```", aliases: ["code", "snippet"]),
        .init(kind: .divider, title: "Trenner", symbol: "minus", shortcut: "---", aliases: ["divider", "linie", "hr"]),
        .init(kind: .image, title: "Bild", symbol: "photo", shortcut: nil, aliases: ["image", "foto", "img"]),
    ]

    /// Filtert nach Titel und Aliassen, ohne Groß-/Kleinschreibung und Akzente.
    /// Treffer am Wortanfang stehen vor Treffern mittendrin.
    public static func matching(_ query: String) -> [SlashCommand] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return all }
        var prefixMatches: [SlashCommand] = []
        var containsMatches: [SlashCommand] = []
        for command in all {
            let haystacks = ([command.title] + command.aliases).map(normalize)
            let words = haystacks.flatMap { $0.split(separator: " ").map(String.init) }
            if words.contains(where: { $0.hasPrefix(needle) }) || haystacks.contains(where: { $0.hasPrefix(needle) }) {
                prefixMatches.append(command)
            } else if haystacks.contains(where: { $0.contains(needle) }) {
                containsMatches.append(command)
            }
        }
        return prefixMatches + containsMatches
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .trimmingCharacters(in: .whitespaces)
    }
}
