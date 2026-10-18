#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import QuillDesign

/// Typografie und Absatzformate pro Blockart.
enum BlockStyle {
    typealias T = QuillDesign.Typography
    typealias S = QuillDesign.Spacing

    static func font(for kind: BlockKind) -> PlatformFont {
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
            .foregroundColor: EditorColor.label,
            .paragraphStyle: paragraphStyle(kind: block.kind, indent: block.indent),
            .quillBlockID: block.id.uuidString,
            .quillBlockKind: block.kind.rawValue,
            .quillIndent: block.indent,
            .quillChecked: block.isChecked,
        ]
        if let language = block.codeLanguage { attributes[.quillCodeLanguage] = language }
        if let ordinal { attributes[.quillOrdinal] = ordinal }
        if block.kind == .quote { attributes[.foregroundColor] = EditorColor.secondaryLabel }
        if block.kind == .todo && block.isChecked {
            attributes[.foregroundColor] = EditorColor.tertiaryLabel
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }
}
