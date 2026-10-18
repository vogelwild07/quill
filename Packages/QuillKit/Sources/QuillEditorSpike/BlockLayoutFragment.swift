#if os(macOS)
import AppKit
import QuillDesign
import QuillEditor

/// Zeichnet die Dekoration eines Blocks: Bullet, Nummer, Checkbox, Zitatbalken,
/// Code-Hintergrund. Alles wird aus den Absatz-Attributen abgeleitet.
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

    private var markerFont: NSFont { BlockStyle.font(for: kind) }

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
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let origin = NSAffineTransform()
        origin.translateX(by: point.x, yBy: point.y)
        origin.concat()

        switch kind {
        case .code: drawCodeBackground()
        case .quote: drawQuoteBar()
        default: break
        }
        NSGraphicsContext.restoreGraphicsState()

        super.draw(at: point, in: context)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        origin.concat()
        switch kind {
        case .bulleted: drawBullet()
        case .numbered: drawNumber()
        case .todo: drawCheckbox()
        case .divider: drawDivider()
        default: break
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCodeBackground() {
        NSColor.quaternarySystemFill.setFill()
        NSBezierPath(roundedRect: codeBackgroundRect, xRadius: 8, yRadius: 8).fill()
    }

    private func drawQuoteBar() {
        let bounds = contentBounds.isNull ? CGRect(x: 0, y: 0, width: 0, height: 20) : contentBounds
        NSColor.controlAccentColor.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: CGRect(x: markerOriginX + 2, y: bounds.minY + 2, width: 3, height: bounds.height - 4), xRadius: 1.5, yRadius: 1.5).fill()
    }

    private func drawBullet() {
        let symbols = ["•", "◦", "▪︎"]
        drawMarker(symbols[indent % symbols.count], alignRight: false)
    }

    private func drawNumber() {
        drawMarker("\(ordinal).", alignRight: true)
    }

    private func drawMarker(_ text: String, alignRight: Bool) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: markerFont.pointSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let step = QuillDesign.Spacing.indentStep
        let x = alignRight ? markerOriginX + step - 6 - size.width : markerOriginX + 6
        let font = attributes[.font] as! NSFont
        string.draw(at: CGPoint(x: x, y: firstBaseline - font.ascender))
    }

    /// Das Attachment reserviert nur Platz; TextKit 2 zeichnet sein Bild nicht zuverlässig.
    private func drawDivider() {
        let line = textLineFragments.first?.typographicBounds ?? CGRect(x: 0, y: 0, width: 0, height: 20)
        NSColor.separatorColor.setFill()
        CGRect(x: markerOriginX, y: (line.midY).rounded(.down), width: contentMaxX - markerOriginX, height: 1).fill()
    }

    private func drawCheckbox() {
        let rect = checkboxRect
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        if isChecked {
            NSColor.controlAccentColor.setFill()
            path.fill()
            let check = NSBezierPath()
            check.move(to: CGPoint(x: rect.minX + 3.5, y: rect.midY))
            check.line(to: CGPoint(x: rect.minX + 6, y: rect.maxY - 3.5))
            check.line(to: CGPoint(x: rect.maxX - 3, y: rect.minY + 3.5))
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            NSColor.tertiaryLabelColor.setStroke()
            path.lineWidth = 1.2
            path.stroke()
        }
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
#endif
