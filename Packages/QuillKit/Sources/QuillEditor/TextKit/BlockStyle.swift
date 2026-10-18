#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import QuillDesign
import QuillModel

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
        case .paragraph, .bulleted, .numbered, .todo, .quote, .divider, .image: .systemFont(ofSize: T.bodySize)
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

    /// Linker Rand samt Listenmarker: Dort enden Griff und ＋, dort beginnt die Einfügelinie.
    static func leadingInset(kind: BlockKind, indent: Int) -> CGFloat {
        textInset(kind: kind, indent: indent) - (kind.isListItem ? S.indentStep : 0)
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
        case .image:
            style.lineHeightMultiple = T.bodyLineHeight
            style.paragraphSpacingBefore = S.blockGap
        case .paragraph, .bulleted, .numbered, .todo, .quote, .divider:
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
        ]
        attributes.merge(block.properties.textAttributes) { _, new in new }
        if let ordinal { attributes[.quillOrdinal] = ordinal }
        if block.kind == .quote { attributes[.foregroundColor] = EditorColor.secondaryLabel }
        if block.kind == .todo && block.isChecked {
            attributes[.foregroundColor] = EditorColor.tertiaryLabel
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    // MARK: Inline

    /// Attribute eines formatierten Textstücks, aufbauend auf der Schrift der Blockart.
    static func inlineAttributes(for style: InlineStyle, kind: BlockKind) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        let marks = style.marks
        if !marks.isEmpty {
            attributes[.quillMarks] = marks.sorted().map(\.rawValue).joined(separator: " ")
        }
        let base = font(for: kind)
        var font = marks.contains(.code)
            ? PlatformFont.monospacedSystemFont(ofSize: (base.pointSize * 0.9).rounded(), weight: .regular)
            : base
        if marks.contains(.bold) || marks.contains(.italic) {
            font = Self.font(font, bold: marks.contains(.bold), italic: marks.contains(.italic))
        }
        if font != base { attributes[.font] = font }
        // Hintergrund von Inline-Code zeichnet `BlockLayoutFragment`.
        if marks.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link = style.link { attributes[.link] = URL(string: link) ?? link }
        return attributes
    }

    /// Inline-Stil aus den Attributen eines Zeichens.
    static func inlineStyle(from attributes: [NSAttributedString.Key: Any]) -> InlineStyle {
        let marks = (attributes[.quillMarks] as? String)?
            .split(separator: " ")
            .map { InlineMark(rawValue: String($0)) } ?? []
        let link: String? = switch attributes[.link] {
        case let url as URL: url.absoluteString
        case let string as String: string
        default: nil
        }
        return InlineStyle(marks: Set(marks), link: link)
    }

    private static func font(_ font: PlatformFont, bold: Bool, italic: Bool) -> PlatformFont {
        #if canImport(AppKit)
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
        #else
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
        #endif
    }
}
