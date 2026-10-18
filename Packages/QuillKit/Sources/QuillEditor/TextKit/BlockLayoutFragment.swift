#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import CoreText
import QuillDesign

/// Zeichnet die Dekoration eines Blocks: Bullet, Nummer, Checkbox, Zitatbalken,
/// Code-Hintergrund, Trenner. Alles wird aus den Absatz-Attributen abgeleitet.
///
/// Gezeichnet wird nur über `CGContext` und CoreText, damit iOS die Klasse teilt.
final class BlockLayoutFragment: NSTextLayoutFragment {
    let kind: BlockKind
    let indent: Int
    let isChecked: Bool
    let ordinal: Int

    override init(textElement: NSTextElement, range rangeInElement: NSTextRange?) {
        let attributes: [NSAttributedString.Key: Any]
        if let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 {
            attributes = paragraph.attributedString.attributes(at: 0, effectiveRange: nil)
        } else {
            attributes = [:]
        }
        kind = (attributes[.quillBlockKind] as? String).flatMap(BlockKind.init(rawValue:)) ?? .paragraph
        indent = attributes[.quillIndent] as? Int ?? 0
        isChecked = attributes[.quillChecked] as? Bool ?? false
        ordinal = attributes[.quillOrdinal] as? Int ?? 1
        super.init(textElement: textElement, range: rangeInElement)
    }

    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    // MARK: Geometrie (Fragment-Koordinaten, y nach unten)

    private var markerFont: PlatformFont { BlockStyle.font(for: kind) }

    /// Grundlinie der ersten Zeile.
    private var firstBaseline: CGFloat {
        guard let line = textLineFragments.first else { return markerFont.ascender }
        return line.typographicBounds.minY + line.glyphOrigin.y
    }

    private var lineFragmentPadding: CGFloat {
        textLayoutManager?.textContainer?.lineFragmentPadding ?? 5
    }

    /// Der lokale Ursprung liegt am Textanfang (Padding + Einrückung), nicht am
    /// Containerrand. Marker werden deshalb in Container-x gerechnet und umgerechnet.
    private func local(_ containerX: CGFloat) -> CGFloat {
        containerX - layoutFragmentFrame.minX
    }

    private var markerOriginX: CGFloat {
        local(lineFragmentPadding + CGFloat(indent) * QuillDesign.Spacing.indentStep)
    }

    /// Rechter Rand der Textspalte in lokalen Koordinaten.
    private var contentMaxX: CGFloat {
        let width = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.maxX
        return local(width - lineFragmentPadding)
    }

    var checkboxRect: CGRect {
        let size: CGFloat = 14
        let centerY = firstBaseline - markerFont.capHeight / 2
        return CGRect(x: markerOriginX + 3, y: centerY - size / 2, width: size, height: size)
    }

    private var contentBounds: CGRect {
        textLineFragments.reduce(CGRect.null) { $0.union($1.typographicBounds) }
    }

    private var codeBackgroundRect: CGRect {
        let padding = QuillDesign.Spacing.codePadding
        let lines = contentBounds.isNull ? CGRect(x: 0, y: 0, width: 0, height: 20) : contentBounds
        return CGRect(
            x: markerOriginX,
            y: lines.minY - padding / 2,
            width: contentMaxX - markerOriginX,
            height: lines.height + padding
        )
    }

    override var renderingSurfaceBounds: CGRect {
        var bounds = super.renderingSurfaceBounds
        if kind == .code { bounds = bounds.union(codeBackgroundRect) }
        if kind == .quote { bounds = bounds.union(CGRect(x: markerOriginX, y: 0, width: 8, height: layoutFragmentFrame.height)) }
        if kind.isListItem { bounds = bounds.union(checkboxRect.insetBy(dx: -4, dy: -4)) }
        return bounds
    }

    // MARK: Zeichnen

    override func draw(at point: CGPoint, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        switch kind {
        case .code: drawCodeBackground(in: context)
        case .quote: drawQuoteBar(in: context)
        default: break
        }
        context.restoreGState()

        super.draw(at: point, in: context)

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        switch kind {
        case .bulleted: drawBullet(in: context)
        case .numbered: drawNumber(in: context)
        case .todo: drawCheckbox(in: context)
        case .divider: drawDivider(in: context)
        default: break
        }
        context.restoreGState()
    }

    private func drawCodeBackground(in context: CGContext) {
        fillRoundedRect(codeBackgroundRect, radius: 8, color: EditorColor.quaternaryFill, in: context)
    }

    private func drawQuoteBar(in context: CGContext) {
        let bounds = contentBounds.isNull ? CGRect(x: 0, y: 0, width: 0, height: 20) : contentBounds
        let bar = CGRect(x: markerOriginX + 2, y: bounds.minY + 2, width: 3, height: bounds.height - 4)
        fillRoundedRect(bar, radius: 1.5, color: EditorColor.accent.withAlphaComponent(0.6), in: context)
    }

    private func drawBullet(in context: CGContext) {
        let symbols = ["•", "◦", "▪︎"]
        drawMarker(symbols[indent % symbols.count], alignRight: false, in: context)
    }

    private func drawNumber(in context: CGContext) {
        drawMarker("\(ordinal).", alignRight: true, in: context)
    }

    /// Marker-Text über CoreText. Der Kontext ist gespiegelt (y nach unten),
    /// deshalb wird die Textmatrix vertikal umgedreht.
    private func drawMarker(_ text: String, alignRight: Bool, in context: CGContext) {
        let font = PlatformFont.monospacedDigitSystemFont(ofSize: markerFont.pointSize, weight: .regular)
        let string = NSAttributedString(string: text, attributes: [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
        let line = CTLineCreateWithAttributedString(string)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let step = QuillDesign.Spacing.indentStep
        let x = alignRight ? markerOriginX + step - 6 - width : markerOriginX + 6

        context.setFillColor(EditorColor.secondaryLabel.cgColor)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: firstBaseline)
        CTLineDraw(line, context)
    }

    /// Das Attachment reserviert nur Platz; TextKit 2 zeichnet sein Bild nicht zuverlässig.
    private func drawDivider(in context: CGContext) {
        let line = textLineFragments.first?.typographicBounds ?? CGRect(x: 0, y: 0, width: 0, height: 20)
        context.setFillColor(EditorColor.separator.cgColor)
        context.fill(CGRect(x: markerOriginX, y: line.midY.rounded(.down), width: contentMaxX - markerOriginX, height: 1))
    }

    private func drawCheckbox(in context: CGContext) {
        let rect = checkboxRect
        let box = Self.roundedRect(rect, radius: 4)
        if isChecked {
            context.addPath(box)
            context.setFillColor(EditorColor.accent.cgColor)
            context.fillPath()

            context.move(to: CGPoint(x: rect.minX + 3.5, y: rect.midY))
            context.addLine(to: CGPoint(x: rect.minX + 6, y: rect.maxY - 3.5))
            context.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY + 3.5))
            context.setLineWidth(1.8)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setStrokeColor(EditorColor.onAccent.cgColor)
            context.strokePath()
        } else {
            context.addPath(box)
            context.setLineWidth(1.2)
            context.setStrokeColor(EditorColor.tertiaryLabel.cgColor)
            context.strokePath()
        }
    }

    private func fillRoundedRect(_ rect: CGRect, radius: CGFloat, color: PlatformColor, in context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.addPath(Self.roundedRect(rect, radius: radius))
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    /// `CGPath(roundedRect:)` bricht ab, wenn der Radius größer als die halbe Seite ist.
    private static func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let radius = max(0, min(radius, rect.width / 2, rect.height / 2))
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}

/// Liefert `BlockLayoutFragment` für jeden Absatz.
final class BlockLayoutDelegate: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        BlockLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
