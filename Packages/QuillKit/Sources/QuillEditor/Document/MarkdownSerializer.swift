import Foundation

/// Wandelt Blöcke in Markdown (CommonMark + Task-Listen) bzw. Klartext um.
public enum MarkdownSerializer {
    /// Markdown für eine Blockfolge. `ordinals` liefert die Nummer nummerierter Punkte.
    public static func markdown(for blocks: [EditorBlock], ordinal: (Int) -> Int) -> String {
        var output = ""
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                output += separator(between: blocks[index - 1], and: block)
            }
            output += line(for: block, ordinal: ordinal(index))
        }
        return output
    }

    /// Markdown für einen Dokumentausschnitt mit korrekter Nummerierung.
    public static func markdown(for document: EditorDocument, blocks range: Range<Int>) -> String {
        let slice = Array(document.blocks[range])
        return markdown(for: slice) { document.listOrdinal(at: range.lowerBound + $0) }
    }

    /// Klartext: ein Block pro Zeile, ohne Markierungen.
    public static func plainText(for blocks: [EditorBlock]) -> String {
        blocks.map { block in
            switch block.kind {
            case .divider: "---"
            case .image: ""
            case .paragraph, .heading1, .heading2, .heading3, .bulleted, .numbered, .todo, .quote, .code:
                block.text
            }
        }
        .joined(separator: "\n")
    }

    private static func separator(between previous: EditorBlock, and next: EditorBlock) -> String {
        let tight = (previous.kind.isListItem && next.kind.isListItem)
            || (previous.kind == .quote && next.kind == .quote)
        return tight ? "\n" : "\n\n"
    }

    private static func line(for block: EditorBlock, ordinal: Int) -> String {
        let indent = String(repeating: "    ", count: block.indent)
        let text = inlineMarkdown(block.content)
        switch block.kind {
        case .paragraph: return indent + text
        case .heading1: return "# " + text
        case .heading2: return "## " + text
        case .heading3: return "### " + text
        case .bulleted: return indent + "- " + text
        case .numbered: return indent + "\(ordinal). " + text
        case .todo: return indent + (block.isChecked ? "- [x] " : "- [ ] ") + text
        case .quote:
            return text.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
        case .code:
            let fence = block.text.contains("```") ? "````" : "```"
            return fence + (block.codeLanguage ?? "") + "\n" + block.text + "\n" + fence
        case .divider: return "---"
        case .image: return "![](\(block.text))"
        }
    }

    // MARK: Inline

    /// Markdown für formatierten Text: `**fett**`, `_kursiv_`, `~~durch~~`, `` `Code` ``,
    /// `[Text](Ziel)`. Leerraum am Rand eines Stücks bleibt außerhalb der Markierungen,
    /// sonst erkennt CommonMark sie nicht.
    public static func inlineMarkdown(_ content: InlineText) -> String {
        guard !content.spans.isEmpty else { return content.text }
        let utf16 = Array(content.text.utf16)
        var output = ""
        var cursor = 0
        func plain(_ range: Range<Int>) -> String {
            String(decoding: utf16[range], as: UTF16.self)
        }
        for span in content.spans {
            if cursor < span.range.lowerBound { output += plain(cursor..<span.range.lowerBound) }
            output += wrap(plain(span.range), in: span.style)
            cursor = span.range.upperBound
        }
        if cursor < utf16.count { output += plain(cursor..<utf16.count) }
        return output
    }

    private static func wrap(_ text: String, in style: InlineStyle) -> String {
        let leading = String(text.prefix { $0.isWhitespace })
        let trailing = String(text.reversed().prefix { $0.isWhitespace }.reversed())
        guard leading.count < text.count else { return text }
        var core = String(text.dropFirst(leading.count).dropLast(trailing.count))

        if style.marks.contains(.code) {
            core = core.contains("`") ? "`` " + core + " ``" : "`" + core + "`"
        }
        if style.marks.contains(.italic) { core = "_" + core + "_" }
        if style.marks.contains(.bold) { core = "**" + core + "**" }
        if style.marks.contains(.strikethrough) { core = "~~" + core + "~~" }
        if let link = style.link { core = "[" + core + "](" + link + ")" }
        return leading + core + trailing
    }
}
