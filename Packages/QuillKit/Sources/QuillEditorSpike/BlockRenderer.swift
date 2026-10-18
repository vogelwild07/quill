#if os(macOS)
import AppKit
import QuillEditor

/// Übersetzt zwischen `EditorDocument` und dem attributierten Text im Textspeicher.
///
/// Invariante: Jeder Block ist genau ein Absatz und endet mit `\n` – auch der letzte.
/// So trägt jeder Absatz mindestens ein Zeichen mit den Block-Attributen.
@MainActor
struct BlockRenderer {
    var images: [UUID: NSImage] = [:]

    /// Anzahl Zeichen eines Blocks im Textspeicher (ohne `\n`).
    static func displayLength(of block: EditorBlock) -> Int {
        block.kind.isAtomic ? 1 : block.length
    }

    func render(_ blocks: ArraySlice<EditorBlock>, ordinals: [UUID: Int]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for block in blocks {
            result.append(paragraph(for: block, ordinal: ordinals[block.id]))
        }
        return result
    }

    func paragraph(for block: EditorBlock, ordinal: Int?) -> NSAttributedString {
        let attributes = BlockStyle.attributes(for: block, ordinal: ordinal)
        let result = NSMutableAttributedString()
        switch block.kind {
        case .divider:
            result.append(NSAttributedString(attachment: DividerAttachment()))
        case .image:
            result.append(NSAttributedString(attachment: ImageAttachment(image: images[block.id])))
        default:
            let text = block.text.replacingOccurrences(of: "\n", with: StorageCharacter.softBreak)
            result.append(NSAttributedString(string: text))
        }
        result.append(NSAttributedString(string: "\n"))
        result.addAttributes(attributes, range: NSRange(location: 0, length: result.length))
        return result
    }

    /// Liest die Blöcke aus dem Textspeicher. Fehlende oder doppelte IDs
    /// (z. B. nach Einfügen) bekommen neue IDs; diese Absätze stehen in `repaired`.
    static func parse(_ storage: NSAttributedString) -> (blocks: [EditorBlock], repaired: [NSRange]) {
        let string = storage.string as NSString
        var blocks: [EditorBlock] = []
        var repaired: [NSRange] = []
        var seen = Set<UUID>()
        var start = 0
        let length = string.length
        while start < length {
            var end = start
            while end < length && string.character(at: end) != StorageCharacter.paragraphEnd { end += 1 }
            let anchor = min(end, length - 1)
            let paragraphRange = NSRange(location: start, length: min(end + 1, length) - start)
            let attributes = storage.attributes(at: anchor, effectiveRange: nil)

            var block = EditorBlock()
            if let raw = attributes[.quillBlockKind] as? String, let kind = BlockKind(rawValue: raw) {
                block.kind = kind
            }
            block.indent = attributes[.quillIndent] as? Int ?? 0
            block.isChecked = attributes[.quillChecked] as? Bool ?? false
            block.codeLanguage = attributes[.quillCodeLanguage] as? String
            if !block.kind.isAtomic {
                block.text = string.substring(with: NSRange(location: start, length: end - start))
                    .replacingOccurrences(of: StorageCharacter.softBreak, with: "\n")
            }
            if let raw = attributes[.quillBlockID] as? String, let id = UUID(uuidString: raw), !seen.contains(id) {
                block.id = id
            } else {
                repaired.append(paragraphRange)
            }
            seen.insert(block.id)
            blocks.append(block)
            start = end + 1
        }
        return (blocks, repaired)
    }

    /// Nummern aller nummerierten Punkte in einem Durchlauf.
    static func ordinals(for document: EditorDocument) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        var counters: [Int] = []
        for block in document.blocks {
            let level = block.indent
            if counters.count > level + 1 { counters.removeLast(counters.count - level - 1) }
            while counters.count <= level { counters.append(0) }
            if block.kind == .numbered {
                counters[level] += 1
                result[block.id] = counters[level]
            } else {
                counters[level] = 0
            }
        }
        return result
    }
}
#endif
