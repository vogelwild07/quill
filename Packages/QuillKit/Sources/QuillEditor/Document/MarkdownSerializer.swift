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
            default: block.text
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
        switch block.kind {
        case .paragraph: return indent + block.text
        case .heading1: return "# " + block.text
        case .heading2: return "## " + block.text
        case .heading3: return "### " + block.text
        case .bulleted: return indent + "- " + block.text
        case .numbered: return indent + "\(ordinal). " + block.text
        case .todo: return indent + (block.isChecked ? "- [x] " : "- [ ] ") + block.text
        case .quote:
            return block.text.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
        case .code:
            let fence = block.text.contains("```") ? "````" : "```"
            return fence + (block.codeLanguage ?? "") + "\n" + block.text + "\n" + fence
        case .divider: return "---"
        case .image: return "![](\(block.text))"
        }
    }
}
