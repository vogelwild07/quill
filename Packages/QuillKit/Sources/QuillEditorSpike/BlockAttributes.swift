#if os(macOS)
import AppKit
import QuillDesign
import QuillEditor

extension NSAttributedString.Key {
    /// Block-ID (`String`, UUID). Liegt auf jedem Zeichen eines Absatzes inkl. `\n`.
    static let quillBlockID = NSAttributedString.Key("de.vogel.quill.blockID")
    /// `BlockKind.rawValue`.
    static let quillBlockKind = NSAttributedString.Key("de.vogel.quill.blockKind")
    static let quillIndent = NSAttributedString.Key("de.vogel.quill.indent")
    static let quillChecked = NSAttributedString.Key("de.vogel.quill.checked")
    static let quillCodeLanguage = NSAttributedString.Key("de.vogel.quill.codeLanguage")
    /// Nummer eines nummerierten Punkts; abgeleitet, wird nach jeder Änderung nachgeführt.
    static let quillOrdinal = NSAttributedString.Key("de.vogel.quill.ordinal")
}

/// Zeichen im Textspeicher.
enum StorageCharacter {
    static let paragraphEnd: unichar = 0x0A
    /// Weicher Umbruch (⇧↩, Code) – im Modell `\n`.
    static let softBreak = "\u{2028}"
    static let attachment = "\u{FFFC}"
}

/// Typografie und Absatzformate pro Blockart.
enum BlockStyle {
    typealias T = QuillDesign.Typography
    typealias S = QuillDesign.Spacing

    static func font(for kind: BlockKind) -> NSFont {
        switch kind {
        case .heading1: .systemFont(ofSize: T.heading1Size, weight: .bold)
        case .heading2: .systemFont(ofSize: T.heading2Size, weight: .semibold)
        case .heading3: .systemFont(ofSize: T.heading3Size, weight: .semibold)
        case .code: .monospacedSystemFont(ofSize: T.codeSize, weight: .regular)
        default: .systemFont(ofSize: T.bodySize)
        }
    }

    /// Linker Rand des Textes eines Blocks (ohne Marker).
    static func textInset(kind: BlockKind, indent: Int) -> CGFloat {
        var inset = CGFloat(indent) * S.indentStep
        if kind.isListItem { inset += S.indentStep }
        if kind == .quote { inset += S.quoteInset }
        if kind == .code { inset += S.codePadding }
        return inset
    }

    static func paragraphStyle(kind: BlockKind, indent: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let inset = textInset(kind: kind, indent: indent)
        style.firstLineHeadIndent = inset
        style.headIndent = inset
        style.paragraphSpacing = S.blockGap
        switch kind {
        case .heading1, .heading2, .heading3:
            style.lineHeightMultiple = T.headingLineHeight
            style.paragraphSpacingBefore = S.beforeHeading
        case .code:
            style.lineHeightMultiple = T.codeLineHeight
            style.tailIndent = -S.codePadding
            style.paragraphSpacingBefore = S.codePadding
            style.paragraphSpacing = S.codePadding + S.blockGap
        default:
            style.lineHeightMultiple = T.bodyLineHeight
        }
        return style
    }

    static func attributes(for block: EditorBlock, ordinal: Int?) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: block.kind),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle(kind: block.kind, indent: block.indent),
            .quillBlockID: block.id.uuidString,
            .quillBlockKind: block.kind.rawValue,
            .quillIndent: block.indent,
            .quillChecked: block.isChecked,
        ]
        if let language = block.codeLanguage { attributes[.quillCodeLanguage] = language }
        if let ordinal { attributes[.quillOrdinal] = ordinal }
        if block.kind == .quote { attributes[.foregroundColor] = NSColor.secondaryLabelColor }
        if block.kind == .todo && block.isChecked {
            attributes[.foregroundColor] = NSColor.tertiaryLabelColor
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }
}
#endif
