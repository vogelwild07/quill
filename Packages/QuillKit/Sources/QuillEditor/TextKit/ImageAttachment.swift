#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import ImageIO
import QuillModel
import Synchronization

/// Bild-Block: reserviert Platz in der Größe des Bildes, skaliert auf die Textbreite.
/// Das Bild selbst zeichnet `BlockLayoutFragment` (wie den Trenner), weil TextKit 2
/// das Bild eines Attachments nicht zuverlässig zeichnet (ADR-015).
final class ImageAttachment: NSTextAttachment {
    let assetID: UUID?

    /// Höhe, solange Größe und Bild noch nicht geladen sind.
    static let placeholderHeight: CGFloat = 120

    init(assetID: UUID?) {
        self.assetID = assetID
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    /// Anzeigegröße: natürliche Größe in Punkten (DPI berücksichtigt), höchstens so
    /// breit wie der Text.
    static func displaySize(pointSize: CGSize?, availableWidth: CGFloat) -> CGSize {
        let width = max(availableWidth, 10)
        guard let pointSize, pointSize.width > 0, pointSize.height > 0 else {
            return CGSize(width: width, height: placeholderHeight)
        }
        let scale = min(1, width / pointSize.width)
        return CGSize(width: (pointSize.width * scale).rounded(), height: (pointSize.height * scale).rounded())
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let pointSize = assetID.flatMap { EditorImageCache.shared.entry(for: $0)?.pointSize }
        let size = Self.displaySize(pointSize: pointSize, availableWidth: proposedLineFragment.width - 4)
        return CGRect(origin: .zero, size: size)
    }

    override func image(
        for bounds: CGRect,
        attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> PlatformImage? {
        // Leer, das Fragment zeichnet.
        #if canImport(AppKit)
        NSImage(size: bounds.size, flipped: false) { _ in true }
        #else
        UIImage()
        #endif
    }
}

/// Dekodierte Bilder für die Anzeige, nach `Asset.id`. Wird von TextKit beim Layout
/// und Zeichnen gelesen (nicht immer auf dem Main Thread), deshalb mit `Mutex`.
final class EditorImageCache: Sendable {
    static let shared = EditorImageCache()

    struct Entry: @unchecked Sendable {
        /// Natürliche Größe in Punkten (Ausrichtung und DPI berücksichtigt).
        let pointSize: CGSize
        /// Für die Anzeige verkleinert; `CGImage` ist unveränderlich.
        let image: CGImage
    }

    /// Höchstens so viele Bilder; danach fliegen die ältesten raus.
    private static let limit = 64
    private let state = Mutex<(entries: [UUID: Entry], order: [UUID])>(([:], []))

    func entry(for id: UUID) -> Entry? {
        state.withLock { $0.entries[id] }
    }

    func store(_ entry: Entry, for id: UUID) {
        state.withLock { state in
            if state.entries.updateValue(entry, forKey: id) == nil { state.order.append(id) }
            while state.order.count > Self.limit {
                state.entries[state.order.removeFirst()] = nil
            }
        }
    }

    /// Dekodiert verkleinert (lange Kante höchstens `maxPixelSize`) mit angewandter
    /// Ausrichtung. Nicht auf dem Main Thread aufrufen.
    static func decode(_ data: Data, maxPixelSize: Int = 2048) -> Entry? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return Entry(pointSize: ImageImport.pointSize(properties), image: image)
    }
}
