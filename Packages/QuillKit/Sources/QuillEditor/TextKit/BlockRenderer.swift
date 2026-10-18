#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Übersetzt zwischen `EditorDocument` und dem attributierten Text im Textspeicher.
///
/// Invariante: Jeder Block ist genau ein Absatz und endet mit `\n` – auch der letzte.
/// So trägt jeder Absatz mindestens ein Zeichen mit den Block-Attributen.
enum BlockRenderer {
    /// Anzahl Zeichen eines Blocks im Textspeicher (ohne `\n`).
    static func displayLength(of block: EditorBlock) -> Int {
        block.kind.isAtomic ? 1 : block.length
    }

    static func render(_ blocks: ArraySlice<EditorBlock>, ordinals: [UUID: Int]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for block in blocks {
            result.append(paragraph(for: block, ordinal: ordinals[block.id]))
        }
        return result
    }

    static func paragraph(for block: EditorBlock, ordinal: Int?) -> NSAttributedString {
        let attributes = BlockStyle.attributes(for: block, ordinal: ordinal)
        let result = NSMutableAttributedString()
        switch block.kind {
        case .divider:
            result.append(NSAttributedString(attachment: DividerAttachment()))
        case .image:
            // Platzhalter; Bilder mit `NSTextAttachmentViewProvider` folgen in Phase 4.
            result.append(NSAttributedString(attachment: NSTextAttachment(data: nil, ofType: nil)))
        default:
            let text = block.text.replacingOccurrences(of: "\n", with: StorageCharacter.softBreak)
            result.append(NSAttributedString(string: text))
        }
        result.append(NSAttributedString(string: "\n"))
        result.addAttributes(attributes, range: NSRange(location: 0, length: result.length))
        addInlineAttributes(of: block, to: result, at: 0)
        return result
    }

    /// Setzt alle Attribute eines Absatzes neu (Block und Inline), z. B. nach einem
    /// Abgleich. `range` umfasst den Absatz inklusive `\n`.
    static func restyle(_ storage: NSMutableAttributedString, block: EditorBlock, ordinal: Int?, range: NSRange) {
        let attributes = BlockStyle.attributes(for: block, ordinal: ordinal)
        if block.kind.isAtomic {
            // `addAttributes`, damit das Attachment bleibt.
            storage.addAttributes(attributes, range: range)
        } else {
            storage.setAttributes(attributes, range: range)
            addInlineAttributes(of: block, to: storage, at: range.location)
        }
    }

    private static func addInlineAttributes(of block: EditorBlock, to storage: NSMutableAttributedString, at start: Int) {
        for span in block.spans {
            let range = NSRange(location: start + span.range.lowerBound, length: span.range.count)
            storage.addAttributes(BlockStyle.inlineAttributes(for: span.style, kind: block.kind), range: range)
        }
    }

    /// Inline-Formatierung im Text eines Absatzes (`body` ohne `\n`).
    static func spans(in storage: NSAttributedString, body: NSRange) -> [InlineSpan] {
        guard body.length > 0 else { return [] }
        var spans: [InlineSpan] = []
        storage.enumerateAttributes(in: body) { attributes, range, _ in
            let style = BlockStyle.inlineStyle(from: attributes)
            guard !style.isPlain else { return }
            let lower = range.location - body.location
            spans.append(InlineSpan(lower..<(lower + range.length), style))
        }
        return InlineText.normalized(spans, length: body.length)
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
                let body = NSRange(location: start, length: end - start)
                block.text = string.substring(with: body)
                    .replacingOccurrences(of: StorageCharacter.softBreak, with: "\n")
                if block.kind.allowsInlineMarks {
                    block.spans = spans(in: storage, body: body)
                }
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
