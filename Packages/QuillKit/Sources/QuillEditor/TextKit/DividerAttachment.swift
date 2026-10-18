#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Trenner: reserviert eine Zeile über die Textbreite. Die Linie selbst zeichnet
/// `BlockLayoutFragment`, weil TextKit 2 das Bild eines Attachments nicht zuverlässig zeichnet.
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
    ) -> PlatformImage? {
        // Leer, sonst entstünden zwei Linien.
        #if canImport(AppKit)
        NSImage(size: bounds.size, flipped: false) { _ in true }
        #else
        UIImage()
        #endif
    }
}
