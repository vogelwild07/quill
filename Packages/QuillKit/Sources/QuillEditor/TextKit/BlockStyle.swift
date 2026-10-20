#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import QuillDesign
import QuillModel

/// Typografie und Absatzformate pro Blockart.
enum BlockStyle {
    typealias Typography = QuillDesign.Typography
    typealias Spacing = QuillDesign.Spacing

    static func font(for kind: BlockKind) -> PlatformFont {
        switch kind {
        case .heading1: .systemFont(ofSize: Typography.heading1Size, weight: .bold)
        case .heading2: .systemFont(ofSize: Typography.heading2Size, weight: .semibold)
        case .heading3: .systemFont(ofSize: Typography.heading3Size, weight: .semibold)
        case .code: .monospacedSystemFont(ofSize: Typography.codeSize, weight: .regular)
        case .paragraph, .bulleted, .numbered, .todo, .quote, .divider, .image: .systemFont(ofSize: Typography.bodySize)
        }
    }

    /// Linker Rand des Textes eines Blocks (ohne Marker).
    static func textInset(kind: BlockKind, indent: Int) -> CGFloat {
        var inset = CGFloat(indent) * Spacing.indentStep
        if kind.isListItem { inset += Spacing.indentStep }
        if kind == .quote { inset += Spacing.quoteInset }
        if kind == .code { inset += Spacing.codePadding }
        return inset
    }

    /// Linker Rand samt Listenmarker: Dort enden Griff und ＋, dort beginnt die Einfügelinie.
    static func leadingInset(kind: BlockKind, indent: Int) -> CGFloat {
        textInset(kind: kind, indent: indent) - (kind.isListItem ? Spacing.indentStep : 0)
    }

    static func paragraphStyle(kind: BlockKind, indent: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let inset = textInset(kind: kind, indent: indent)
        style.firstLineHeadIndent = inset
        style.headIndent = inset
        style.paragraphSpacing = Spacing.blockGap
        switch kind {
        case .heading1, .heading2, .heading3:
            style.lineHeightMultiple = Typography.headingLineHeight
            style.paragraphSpacingBefore = Spacing.beforeHeading
        case .code:
            style.lineHeightMultiple = Typography.codeLineHeight
            style.tailIndent = -Spacing.codePadding
            style.paragraphSpacingBefore = Spacing.codePadding
            style.paragraphSpacing = Spacing.codePadding + Spacing.blockGap
        case .image:
            style.lineHeightMultiple = Typography.bodyLineHeight
            style.paragraphSpacingBefore = Spacing.blockGap
        case .paragraph, .bulleted, .numbered, .todo, .quote, .divider:
            style.lineHeightMultiple = Typography.bodyLineHeight
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
        switch block.kind {
        case .heading1, .heading2, .heading3: attributes[.foregroundColor] = EditorColor.heading
        case .quote: attributes[.foregroundColor] = EditorColor.secondaryLabel
        case .todo where block.isChecked:
            attributes[.foregroundColor] = EditorColor.tertiaryLabel
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        case .paragraph, .bulleted, .numbered, .todo, .code, .divider, .image: break
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
