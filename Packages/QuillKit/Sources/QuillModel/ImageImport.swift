import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Bereitet Bilddaten für ein `Asset` vor (ADR-015).
///
/// - Bis `maxOriginalBytes` bleibt das Original erhalten (PNG, JPEG, HEIC, GIF),
///   andere Formate (z. B. TIFF aus der Zwischenablage) werden PNG.
/// - Größere Bilder werden auf höchstens `maxPixelSize` Pixel Kantenlänge
///   heruntergerechnet, nie abgelehnt.
/// - GPS-Daten werden immer entfernt; Ausrichtung, Auflösung (DPI) und übrige
///   Metadaten bleiben. Beim Verkleinern wird die DPI mitskaliert, damit das Bild
///   in derselben Größe erscheint.
///   Standortangaben in der MakerNote des Herstellers oder in eigenen XMP-Feldern
///   kann ImageIO nicht filtern.
public enum ImageImport {
    public static let maxOriginalBytes = 20 * 1024 * 1024
    public static let maxPixelSize = 4096

    public struct Prepared: Sendable {
        public var data: Data
        public var uti: String
        /// Größe in Pixeln, wie das Bild angezeigt wird (Ausrichtung berücksichtigt).
        public var pixelWidth: Int
        public var pixelHeight: Int
        public var wasDownscaled: Bool
    }

    public enum Failure: Error, Equatable {
        case unreadable
    }

    private static let keptTypes: Set<String> = [
        UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.gif.identifier,
    ]

    /// Günstige Prüfung vor dem Einfügen: Kopf und Eigenschaften lesbar, ohne zu dekodieren.
    public static func isReadable(_ data: Data) -> Bool {
        readable(data) != nil
    }

    private static func readable(_ data: Data) -> (source: CGImageSource, type: String, properties: [CFString: Any])? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return (source, type, properties)
    }

    public static func prepare(_ data: Data, maxOriginalBytes: Int = maxOriginalBytes) throws -> Prepared {
        guard let (source, type, properties) = readable(data) else { throw Failure.unreadable }

        if data.count > maxOriginalBytes {
            return try downscaled(source, properties: properties)
        }
        let (width, height) = displaySize(properties)
        if keptTypes.contains(type), let copy = copyWithoutGPS(source, type: type) {
            return Prepared(data: copy, uti: type, pixelWidth: width, pixelHeight: height, wasDownscaled: false)
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let png = encode(image, type: UTType.png.identifier, properties: withoutGPS(properties))
        else { throw Failure.unreadable }
        return Prepared(data: png, uti: UTType.png.identifier, pixelWidth: width, pixelHeight: height, wasDownscaled: false)
    }

    /// Kopiert ohne neu zu komprimieren; `nil`, wenn das Format das nicht kann.
    private static func copyWithoutGPS(_ source: CGImageSource, type: String) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type as CFString, CGImageSourceGetCount(source), nil)
        else { return nil }
        // Ohne `kCGImageDestinationMetadata` verwirft ImageIO alle Metadaten, auch die
        // Ausrichtung. Deshalb die der Quelle mitgeben und nur GPS ausschließen.
        var options: [CFString: Any] = [kCGImageMetadataShouldExcludeGPS: true]
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            options[kCGImageDestinationMetadata] = metadata
        }
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil) else { return nil }
        return output as Data
    }

    /// Verkleinert mit angewandter Ausrichtung; das Ergebnis steht deshalb aufrecht.
    private static func downscaled(_ source: CGImageSource, properties: [CFString: Any]) throws -> Prepared {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { throw Failure.unreadable }
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let type = hasAlpha ? UTType.png.identifier : UTType.jpeg.identifier
        var kept = withoutGPS(properties)
        let (originalWidth, originalHeight) = displaySize(properties)
        let factor = Double(max(image.width, image.height)) / Double(max(originalWidth, originalHeight, 1))
        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            if let dpi = (properties[key] as? NSNumber)?.doubleValue { kept[key] = dpi * factor }
        }
        kept[kCGImagePropertyOrientation] = 1
        kept[kCGImagePropertyTIFFDictionary] = (kept[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?
            .filter { $0.key != kCGImagePropertyTIFFOrientation }
        kept[kCGImagePropertyPixelWidth] = nil
        kept[kCGImagePropertyPixelHeight] = nil
        if !hasAlpha { kept[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        guard let data = encode(image, type: type, properties: kept) else { throw Failure.unreadable }
        return Prepared(data: data, uti: type, pixelWidth: image.width, pixelHeight: image.height, wasDownscaled: true)
    }

    private static func encode(_ image: CGImage, type: String, properties: [CFString: Any]) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func withoutGPS(_ properties: [CFString: Any]) -> [CFString: Any] {
        properties.filter { $0.key != kCGImagePropertyGPSDictionary }
    }

    /// Natürliche Größe in Punkten wie in Apple-Apps: 144 DPI = 2 Pixel pro Punkt.
    /// Ohne oder mit unplausibler DPI (unter 72) gilt 1 Pixel = 1 Punkt.
    public static func pointSize(_ properties: [CFString: Any]) -> CGSize {
        let (width, height) = displaySize(properties)
        func scale(_ key: CFString) -> Double {
            let dpi = (properties[key] as? NSNumber)?.doubleValue ?? 72
            return dpi >= 72 ? dpi / 72 : 1
        }
        // Die DPI-Angaben beziehen sich aufs gespeicherte Bild; bei 90° gedreht tauschen.
        let rotated = (properties[kCGImagePropertyOrientation] as? Int ?? 1) >= 5
        let scaleX = scale(rotated ? kCGImagePropertyDPIHeight : kCGImagePropertyDPIWidth)
        let scaleY = scale(rotated ? kCGImagePropertyDPIWidth : kCGImagePropertyDPIHeight)
        return CGSize(width: Double(width) / scaleX, height: Double(height) / scaleY)
    }

    /// Ausrichtungen 5–8 drehen um 90°: Breite und Höhe tauschen.
    private static func displaySize(_ properties: [CFString: Any]) -> (Int, Int) {
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? (height, width) : (width, height)
    }
}
