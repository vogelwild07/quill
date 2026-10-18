#if os(macOS)
import AppKit

/// Trenner: horizontale Linie über die Textbreite.
final class DividerAttachment: NSTextAttachment {
    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        CGRect(x: 0, y: -4, width: max(proposedLineFragment.width - 4, 10), height: 17)
    }

    override func image(
        for bounds: CGRect,
        attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSImage? {
        // Leer: Die Linie zeichnet `BlockLayoutFragment`, sonst entstünden zwei Linien.
        NSImage(size: bounds.size, flipped: false) { _ in true }
    }
}

/// Bild, skaliert auf die Textbreite.
final class ImageAttachment: NSTextAttachment {
    convenience init(image: NSImage?) {
        self.init(data: nil, ofType: nil)
        self.image = image
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        guard let size = image?.size, size.width > 0 else {
            return CGRect(x: 0, y: 0, width: 200, height: 120)
        }
        let maxWidth = max(proposedLineFragment.width - 4, 40)
        let scale = min(1, maxWidth / size.width)
        return CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
    }
}
#endif
