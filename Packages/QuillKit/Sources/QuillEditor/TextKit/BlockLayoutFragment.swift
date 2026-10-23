#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import CoreText
import QuillDesign
import QuillEditorCore
import QuillModel

/// Zeichnet die Dekoration eines Blocks: Bullet, Nummer, Checkbox, Zitatbalken,
/// Code-Hintergrund, Hintergrund von Inline-Code, Trenner. Alles wird aus den
/// Absatz-Attributen abgeleitet.
///
/// Gezeichnet wird nur über `CGContext` und CoreText, damit iOS die Klasse teilt.
final class BlockLayoutFragment: NSTextLayoutFragment {
    let kind: BlockKind
    let indent: Int
    let isChecked: Bool
    let ordinal: Int
    let assetID: UUID?
    /// Vom Sync wiederhergestellt (ADR-029); zeigt das Zeichen am rechten Rand.
    let isRestored: Bool
    /// Block-ID aus dem Absatz, für den Fokus-Modus.
    let blockID: UUID?
    /// Im Fokus-Modus außerhalb der Auswahl: mit den abgedunkelten Farben gezeichnet
    /// (`EditorColor.drawingDimmed`), Bilder mit `EditorColor.dimmedAlpha`.
    /// Beim Zeichnen gelesen, nicht beim Anlegen: TextKit verwendet Fragmente beim
    /// Neu-Layouten wieder.
    var isDimmed: Bool {
        guard let blockID, let focused = (textLayoutManager?.delegate as? BlockLayoutDelegate)?.focusedBlocks else { return false }
        return !focused.contains(blockID)
    }

    override init(textElement: NSTextElement, range rangeInElement: NSTextRange?) {
        let attributes: [NSAttributedString.Key: Any]
        if let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 {
            attributes = paragraph.attributedString.attributes(at: 0, effectiveRange: nil)
        } else {
            attributes = [:]
        }
        kind = (attributes[.quillBlockKind] as? String).flatMap(BlockKind.init(rawValue:)) ?? .paragraph
        let properties = BlockProperties(textAttributes: attributes)
        indent = properties.indent
        isChecked = properties.isChecked
        ordinal = attributes[.quillOrdinal] as? Int ?? 1
        assetID = properties.assetID
        isRestored = properties.isRestored
        blockID = (attributes[.quillBlockID] as? String).flatMap(UUID.init(uuidString:))
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
        let size = QuillDesign.EditorLayout.checkboxSize
        let centerY = firstBaseline - markerFont.capHeight / 2
        return CGRect(x: markerOriginX + 3, y: centerY - size / 2, width: size, height: size)
    }

    /// Zeichen am rechten Rand (11.6, 15.4): Konflikt vor „wiederhergestellt“ vor
    /// Erinnerung. Beim Zeichnen gelesen, wie `isDimmed`.
    var marker: BlockMarker? {
        let delegate = textLayoutManager?.delegate as? BlockLayoutDelegate
        if let blockID, delegate?.conflictBlocks.contains(blockID) == true {
            return .conflict
        }
        if isRestored { return .restored }
        if let blockID, delegate?.reminderBlocks.contains(blockID) == true {
            return .reminder
        }
        return nil
    }

    /// Feld des Zeichens rechts neben der Textspalte, auf Höhe der ersten Zeile.
    var markerRect: CGRect {
        let size = QuillDesign.EditorLayout.blockMarkerSize
        let centerY = firstBaseline - markerFont.capHeight / 2
        return CGRect(x: contentMaxX + QuillDesign.EditorLayout.blockMarkerGap, y: centerY - size / 2, width: size, height: size)
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

    /// Hintergrund von Inline-Code, je Zeile ein Rechteck. Höhe aus der Schrift um die
    /// Grundlinie, nicht aus der Zeile: so bleibt er sicher in seiner Zeile (statt
    /// `.backgroundColor`, das einmal in die Zeile darüber reichte).
    var inlineCodeRects: [CGRect] {
        guard kind.allowsInlineMarks,
              let string = (textElement as? NSTextParagraph)?.attributedString, string.length > 0 else { return [] }
        var runs: [(range: NSRange, font: PlatformFont?)] = []
        string.enumerateAttribute(.quillMarks, in: NSRange(location: 0, length: string.length)) { value, range, _ in
            guard let marks = value as? String, marks.split(separator: " ").contains(Substring(InlineMark.code.rawValue)) else { return }
            runs.append((range, string.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont))
        }
        guard !runs.isEmpty else { return [] }
        var rects: [CGRect] = []
        for line in textLineFragments {
            let lineRange = line.characterRange
            let baseline = line.typographicBounds.minY + line.glyphOrigin.y
            for run in runs {
                let overlap = NSIntersectionRange(run.range, lineRange)
                guard overlap.length > 0 else { continue }
                // Ein Umbruch am Zeilenende hat dieselbe Position wie das Zeichen davor,
                // wird also nicht mit unterlegt (Test `trailingSoftBreakIsNotUnderlaid`).
                let end = NSMaxRange(overlap)
                let startX = line.locationForCharacter(at: overlap.location).x
                let endX = line.locationForCharacter(at: end).x
                let font = run.font ?? markerFont
                let padding: CGFloat = 2
                let bounds = line.typographicBounds
                let top = max(bounds.minY, baseline - font.ascender - 1)
                let bottom = min(bounds.maxY, baseline - font.descender + 1)
                rects.append(CGRect(x: bounds.minX + startX - padding, y: top, width: endX - startX + 2 * padding, height: bottom - top))
            }
        }
        return rects
    }

    override var renderingSurfaceBounds: CGRect {
        var bounds = super.renderingSurfaceBounds
        for rect in inlineCodeRects { bounds = bounds.union(rect) }
        if kind == .code { bounds = bounds.union(codeBackgroundRect) }
        if kind == .quote { bounds = bounds.union(CGRect(x: markerOriginX, y: 0, width: 8, height: layoutFragmentFrame.height)) }
        if kind.isListItem { bounds = bounds.union(checkboxRect.insetBy(dx: -4, dy: -4)) }
        if kind == .image { bounds = bounds.union(imageRect) }
        // Immer, nicht nur mit Zeichen: Ein Zeichen kommt ohne neues Layout dazu.
        bounds = bounds.union(markerRect.insetBy(dx: -2, dy: -2))
        return bounds
    }

    // MARK: Zeichnen

    override func draw(at point: CGPoint, in context: CGContext) {
        guard isDimmed else { return drawBlock(at: point, in: context) }
        // Farben je Rolle statt einer Deckkraft für den ganzen Block: Schwächere Rollen
        // (Zitat, Marker, Erledigt) dürfen nicht unter ihren Mindestkontrast fallen.
        EditorColor.drawingDimmed { drawBlock(at: point, in: context) }
    }

    private func drawBlock(at point: CGPoint, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        switch kind {
        case .code: drawCodeBackground(in: context)
        case .quote: drawQuoteBar(in: context)
        case .paragraph, .heading1, .heading2, .heading3, .bulleted, .numbered, .todo, .divider, .image: break
        }
        for rect in inlineCodeRects {
            fillRoundedRect(rect, radius: QuillDesign.Radius.small, color: EditorColor.codeBackground, in: context)
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
        case .image: drawImage(in: context)
        case .paragraph, .heading1, .heading2, .heading3, .quote, .code: break
        }
        switch marker {
        case .conflict: drawConflictMarker(in: context)
        case .restored: drawRestoredMarker(in: context)
        case .reminder: drawReminderMarker(in: context)
        case nil: break
        }
        context.restoreGState()
    }

    /// Zwei versetzte Rahmen: zwei Fassungen.
    private func drawConflictMarker(in context: CGContext) {
        let rect = markerRect.insetBy(dx: 1, dy: 1)
        let side = rect.width * 0.68
        let back = CGRect(x: rect.maxX - side, y: rect.minY, width: side, height: side)
        let front = CGRect(x: rect.minX, y: rect.maxY - side, width: side, height: side)
        context.setLineWidth(1.5)
        context.setStrokeColor(EditorColor.accent.cgColor)
        context.addPath(Self.roundedRect(back, radius: 2))
        context.strokePath()
        context.addPath(Self.roundedRect(front, radius: 2))
        context.setFillColor(EditorColor.background.cgColor)
        context.drawPath(using: .fillStroke)
    }

    /// Pfeil im Bogen zurück: wiederhergestellt.
    private func drawRestoredMarker(in context: CGContext) {
        let rect = markerRect.insetBy(dx: 2, dy: 2)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2
        // Kontext mit y nach unten: Der Bogen beginnt oben und läuft gegen den Uhrzeigersinn.
        let start = -CGFloat.pi / 2, end = start + 1.6 * .pi
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(EditorColor.secondary.cgColor)
        context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        context.strokePath()
        let tip = CGPoint(x: center.x, y: center.y - radius)
        context.move(to: CGPoint(x: tip.x + 3.5, y: tip.y - 3))
        context.addLine(to: tip)
        context.addLine(to: CGPoint(x: tip.x + 3.5, y: tip.y + 3))
        context.strokePath()
    }

    /// Glocke: Erinnerung geplant (15.4).
    private func drawReminderMarker(in context: CGContext) {
        let rect = markerRect.insetBy(dx: 2, dy: 1.5)
        let rimY = rect.maxY - 3
        let domeRadius = rect.width * 0.32
        let top = CGPoint(x: rect.midX, y: rect.minY + domeRadius + 1)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(EditorColor.secondary.cgColor)
        // Kontext mit y nach unten: Kuppel oben, Flanken zum Rand, Rand als Linie.
        context.move(to: CGPoint(x: rect.minX + 1, y: rimY))
        context.addLine(to: CGPoint(x: top.x - domeRadius, y: rimY - 3))
        context.addLine(to: CGPoint(x: top.x - domeRadius, y: top.y))
        context.addArc(center: top, radius: domeRadius, startAngle: .pi, endAngle: 0, clockwise: false)
        context.addLine(to: CGPoint(x: top.x + domeRadius, y: rimY - 3))
        context.addLine(to: CGPoint(x: rect.maxX - 1, y: rimY))
        context.closePath()
        context.strokePath()
        context.setFillColor(EditorColor.secondary.cgColor)
        context.fillEllipse(in: CGRect(x: rect.midX - 1.5, y: rimY + 0.5, width: 3, height: 3))
    }

    private func drawCodeBackground(in context: CGContext) {
        fillRoundedRect(codeBackgroundRect, radius: QuillDesign.Radius.large, color: EditorColor.codeBackground, in: context)
    }

    private func drawQuoteBar(in context: CGContext) {
        let bounds = contentBounds.isNull ? CGRect(x: 0, y: 0, width: 0, height: 20) : contentBounds
        let bar = CGRect(x: markerOriginX + 2, y: bounds.minY + 2, width: QuillDesign.EditorLayout.quoteBarWidth, height: bounds.height - 4)
        fillRoundedRect(bar, radius: QuillDesign.EditorLayout.quoteBarWidth / 2, color: EditorColor.quoteBar, in: context)
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

        context.setFillColor(EditorColor.secondary.cgColor)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: firstBaseline)
        CTLineDraw(line, context)
    }

    /// Das Attachment reserviert nur Platz; TextKit 2 zeichnet sein Bild nicht zuverlässig.
    private func drawDivider(in context: CGContext) {
        let line = textLineFragments.first?.typographicBounds ?? CGRect(x: 0, y: 0, width: 0, height: 20)
        context.setFillColor(EditorColor.control.cgColor)
        context.fill(CGRect(x: markerOriginX, y: line.midY.rounded(.down), width: contentMaxX - markerOriginX, height: 1))
    }

    /// Rechteck des Bildes: auf der Grundlinie, wo das Attachment Platz reserviert hat.
    var imageRect: CGRect {
        let entry = assetID.flatMap { EditorImageCache.shared.entry(for: $0) }
        let size = ImageAttachment.displaySize(pointSize: entry?.pointSize, availableWidth: contentMaxX - markerOriginX - 4)
        return CGRect(x: markerOriginX, y: firstBaseline - size.height, width: size.width, height: size.height)
    }

    /// Bild aus `EditorImageCache`, bis es geladen ist eine Fläche in der Farbe der Codeblöcke.
    private func drawImage(in context: CGContext) {
        let rect = imageRect
        guard let image = assetID.flatMap({ EditorImageCache.shared.entry(for: $0)?.image }) else {
            fillRoundedRect(rect, radius: QuillDesign.Radius.medium, color: EditorColor.codeBackground, in: context)
            return
        }
        // Der Kontext ist gespiegelt (y nach unten), `draw` erwartet y nach oben.
        context.saveGState()
        context.addPath(Self.roundedRect(rect, radius: QuillDesign.Radius.small))
        context.clip()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        if isDimmed { context.setAlpha(EditorColor.dimmedAlpha) }
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    private func drawCheckbox(in context: CGContext) {
        let rect = checkboxRect
        let box = Self.roundedRect(rect, radius: QuillDesign.Radius.small)
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
            context.setStrokeColor(EditorColor.checkboxBorder.cgColor)
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

/// Zeichen am rechten Rand eines Blocks (11.6).
public enum BlockMarker: Sendable {
    /// Zwei Fassungen nach dem Abgleich; der Nutzer wählt.
    case conflict
    /// Vom Sync wiederhergestellt (Löschen gegen Bearbeiten, ADR-026).
    case restored
    /// Erinnerung an ein To-do geplant (15.4, ADR-033).
    case reminder
}

/// Liefert `BlockLayoutFragment` für jeden Absatz.
final class BlockLayoutDelegate: NSObject, NSTextLayoutManagerDelegate {
    /// Fokus-Modus: Blöcke mit Auswahl oder Cursor; alle anderen werden abgedunkelt
    /// (`BlockLayoutFragment.isDimmed`). `nil` dunkelt nichts ab. Nach einer Änderung
    /// die betroffenen Absätze neu zeichnen.
    var focusedBlocks: Set<UUID>?
    /// Blöcke mit einem Konflikt aus dem Abgleich (`BlockLayoutFragment.marker`).
    var conflictBlocks: Set<UUID> = []
    /// Blöcke mit geplanter Erinnerung (`BlockLayoutFragment.marker`).
    var reminderBlocks: Set<UUID> = []

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        BlockLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
