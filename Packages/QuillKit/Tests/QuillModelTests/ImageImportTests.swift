import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import QuillModel

/// Testbilder werden im Test erzeugt; keine Bilddateien im Repo.
enum TestImages {
    static func make(width: Int, height: Int, type: UTType, properties: [CFString: Any] = [:], alpha: Bool = false) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.2, blue: 0.1, alpha: alpha ? 0.5 : 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    /// JPEG mit Standort und Ausrichtung 6 (um 90° gedreht), wie vom iPhone.
    static func photoWithLocation(width: Int = 40, height: Int = 20) -> Data {
        make(width: width, height: height, type: .jpeg, properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 52.52, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 13.40, kCGImagePropertyGPSLongitudeRef: "E",
            ],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Testfoto"],
        ])
    }

    static func properties(of data: Data) -> [CFString: Any] {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    static func type(of data: Data) -> String? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
    }
}

@Suite("Bilder: Import")
struct ImageImportTests {
    @Test func testPhotoReallyHasLocation() {
        // Sonst bewiese der nächste Test nichts.
        #expect(TestImages.properties(of: TestImages.photoWithLocation())[kCGImagePropertyGPSDictionary] != nil)
    }

    @Test func removesLocationButKeepsOrientationAndOtherMetadata() throws {
        let prepared = try ImageImport.prepare(TestImages.photoWithLocation())
        let properties = TestImages.properties(of: prepared.data)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(properties[kCGImagePropertyOrientation] as? Int == 6)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifUserComment] as? String == "Testfoto")
        #expect(prepared.uti == UTType.jpeg.identifier)
        // Angezeigte Größe: gedreht.
        #expect(prepared.pixelWidth == 20 && prepared.pixelHeight == 40)
        #expect(!prepared.wasDownscaled)
    }

    @Test func keepsPNGAsPNG() throws {
        let png = TestImages.make(width: 30, height: 10, type: .png, alpha: true)
        let prepared = try ImageImport.prepare(png)
        #expect(prepared.uti == UTType.png.identifier)
        #expect(prepared.pixelWidth == 30 && prepared.pixelHeight == 10)
    }

    @Test func convertsTIFFToPNG() throws {
        let tiff = TestImages.make(width: 12, height: 8, type: .tiff)
        let prepared = try ImageImport.prepare(tiff)
        #expect(prepared.uti == UTType.png.identifier)
        #expect(TestImages.type(of: prepared.data) == UTType.png.identifier)
        #expect(prepared.pixelWidth == 12 && prepared.pixelHeight == 8)
    }

    @Test func largeImagesAreDownscaledNotRejected() throws {
        let photo = TestImages.photoWithLocation(width: 5000, height: 100)
        let prepared = try ImageImport.prepare(photo, maxOriginalBytes: 1000)
        #expect(prepared.wasDownscaled)
        // Ausrichtung angewandt: 100 × 5000, dann auf 4096 begrenzt.
        #expect(max(prepared.pixelWidth, prepared.pixelHeight) == ImageImport.maxPixelSize)
        #expect(prepared.pixelHeight > prepared.pixelWidth)
        let properties = TestImages.properties(of: prepared.data)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == prepared.pixelHeight)
    }

    @Test func smallButHeavyImagesKeepTheirSize() throws {
        let png = TestImages.make(width: 50, height: 40, type: .png, alpha: true)
        let prepared = try ImageImport.prepare(png, maxOriginalBytes: 10)
        #expect(prepared.wasDownscaled)
        #expect(prepared.pixelWidth == 50 && prepared.pixelHeight == 40)
        #expect(prepared.uti == UTType.png.identifier)
    }

    // MARK: Auflösung (DPI)

    @Test func pointSizeFollowsDPI() {
        let retina: [CFString: Any] = [kCGImagePropertyPixelWidth: 200, kCGImagePropertyPixelHeight: 100,
                                       kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144]
        #expect(ImageImport.pointSize(retina) == CGSize(width: 100, height: 50))
        let plain: [CFString: Any] = [kCGImagePropertyPixelWidth: 200, kCGImagePropertyPixelHeight: 100]
        #expect(ImageImport.pointSize(plain) == CGSize(width: 200, height: 100))
        var implausible = retina
        implausible[kCGImagePropertyDPIWidth] = 1
        implausible[kCGImagePropertyDPIHeight] = 1
        #expect(ImageImport.pointSize(implausible) == CGSize(width: 200, height: 100))
        var rotated = retina
        rotated[kCGImagePropertyOrientation] = 6
        #expect(ImageImport.pointSize(rotated) == CGSize(width: 50, height: 100))
    }

    @Test func importKeepsDPI() throws {
        let screenshot = TestImages.make(width: 200, height: 100, type: .png, properties: [
            kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144,
        ])
        let prepared = try ImageImport.prepare(screenshot)
        #expect(ImageImport.pointSize(TestImages.properties(of: prepared.data)) == CGSize(width: 100, height: 50))
    }

    @Test func downscalingKeepsPointSize() throws {
        let large = TestImages.make(width: 5000, height: 100, type: .png, properties: [
            kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144,
        ])
        let prepared = try ImageImport.prepare(large, maxOriginalBytes: 1000)
        #expect(prepared.pixelWidth == ImageImport.maxPixelSize)
        let size = ImageImport.pointSize(TestImages.properties(of: prepared.data))
        #expect(abs(size.width - 2500) < 2)
        #expect(abs(size.height - 50) < 2)
    }

    @Test func unreadableDataThrows() {
        #expect(throws: ImageImport.Failure.unreadable) { try ImageImport.prepare(Data("kein Bild".utf8)) }
    }
}
