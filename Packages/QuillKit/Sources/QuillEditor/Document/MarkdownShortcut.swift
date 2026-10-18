import Foundation

extension EditorDocument {
    /// Wandelt ein Markdown-Kürzel am Blockanfang um, z. B. `# ` → Überschrift 1.
    ///
    /// Aufrufen, nachdem ein Leerzeichen (oder bei `---` der dritte Strich) eingefügt
    /// wurde; `position` ist der Cursor danach. Greift nur in normalen Absätzen und
    /// nur, wenn der Text vor dem Cursor genau das Kürzel ist.
    /// Gibt die neue Cursorposition zurück oder `nil`, wenn kein Kürzel passt.
    public mutating func applyMarkdownShortcut(at position: BlockPosition) -> BlockPosition? {
        let index = position.block
        let block = blocks[index]
        guard block.kind == .paragraph else { return nil }
        let (prefix, rest) = Self.split(block.text, at: position.offset)

        if prefix == "---" && rest.isEmpty {
            setKind(.divider, at: index)
            return BlockPosition(block: index + 1, offset: 0)
        }
        guard prefix.hasSuffix(" ") else { return nil }
        let marker = String(prefix.dropLast())
        guard let (kind, checked, language) = Self.shortcutKind(for: marker) else { return nil }

        setKind(kind, at: index)
        blocks[index].text = rest
        blocks[index].isChecked = checked
        blocks[index].codeLanguage = language
        return BlockPosition(block: index, offset: 0)
    }

    private static func shortcutKind(for marker: String) -> (BlockKind, Bool, String?)? {
        switch marker {
        case "#": return (.heading1, false, nil)
        case "##": return (.heading2, false, nil)
        case "###": return (.heading3, false, nil)
        case "-", "*", "+": return (.bulleted, false, nil)
        case "[]", "[ ]": return (.todo, false, nil)
        case "[x]", "[X]": return (.todo, true, nil)
        case ">": return (.quote, false, nil)
        default: break
        }
        if marker.hasPrefix("```") {
            let language = marker.dropFirst(3)
            guard !language.contains("`") else { return nil }
            return (.code, false, language.isEmpty ? nil : String(language))
        }
        if marker.hasSuffix("."), marker.dropLast().allSatisfy(\.isASCII), Int(marker.dropLast()) != nil {
            return (.numbered, false, nil)
        }
        return nil
    }
}
