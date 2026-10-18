#if canImport(AppKit)
import AppKit

/// Einfügen-Knopf ＋ zwischen Griff und Block: neuer Block darunter (⌥: darüber) mit
/// offenem Slash-Menü; Escape nimmt den Klick zurück. Erscheint mit dem Griff bei Hover.
final class BlockInsertButton: NSView {
    weak var textView: BlockTextView?
    var characterOffset = 0

    /// Unter dem Mauszeiger kräftiger (Systemfarben, hell und dunkel).
    var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("editor.insert")
        setAccessibilityLabel(String(localized: "Block einfügen", bundle: .module))
        setAccessibilityHelp(String(localized: "Mit Wahltaste darüber einfügen", bundle: .module))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    /// ＋ als zwei Striche; gezeichnet statt SF Symbol, damit die Farbe stimmt.
    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.quaternarySystemFill.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 4, yRadius: 4).fill()
        }
        (isHovered ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setStroke()
        let center = CGPoint(x: bounds.midX.rounded(), y: bounds.midY.rounded())
        let arm: CGFloat = 5
        let plus = NSBezierPath()
        plus.lineWidth = 1.5
        plus.lineCapStyle = .round
        plus.move(to: CGPoint(x: center.x - arm, y: center.y))
        plus.line(to: CGPoint(x: center.x + arm, y: center.y))
        plus.move(to: CGPoint(x: center.x, y: center.y - arm))
        plus.line(to: CGPoint(x: center.x, y: center.y + arm))
        plus.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override var isHidden: Bool {
        didSet { if isHidden { isHovered = false } }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseDown(with event: NSEvent) {
        insert(above: event.modifierFlags.contains(.option))
    }

    override func accessibilityPerformPress() -> Bool {
        insert(above: false)
        return true
    }

    private func insert(above: Bool) {
        textView?.editor?.insertBlockWithMenu(nearCharacter: characterOffset, above: above)
    }
}
#endif
