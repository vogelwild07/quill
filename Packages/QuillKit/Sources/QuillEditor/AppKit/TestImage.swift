#if canImport(AppKit) && DEBUG
import AppKit
import OSLog

/// Startargument `-QuillTestImage <Breite>x<Höhe>` oder `-QuillTestImage heavy`:
/// Die App erzeugt das Testbild selbst und legt es in ihre eigene Zwischenablage
/// (`-QuillPasteboardName`). So setzen UI-Tests Bilder ein, ohne dass ein anderer
/// Prozess die Zwischenablage füllt; das sperrt der Datenschutz („Einsetzen aus
/// anderen Apps“). Nur im Debug-Build, nur aus der Kommandozeile, nie in die
/// allgemeine Zwischenablage.
enum TestImage {
    static let argument = "QuillTestImage"

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "editor")

    /// Legt das Testbild aus den Startargumenten in `pasteboard`. Gibt zurück, ob
    /// ein Bild gelegt wurde.
    @discardableResult
    static func put(arguments: [String], on pasteboard: NSPasteboard) -> Bool {
        guard pasteboard.name != .general,
              let index = arguments.firstIndex(of: "-\(argument)"), arguments.indices.contains(index + 1),
              let data = png(spec: arguments[index + 1]) else { return false }
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        logger.notice("Testbild in eigener Zwischenablage (\(argument, privacy: .public))")
        return true
    }

    /// `heavy`: Rauschen, kaum komprimierbar, ein PNG über 20 MB. Sonst einfarbig
    /// in `<Breite>x<Höhe>` (je 1…4000).
    static func png(spec: String) -> Data? {
        if spec == "heavy" { return noise(width: 2700, height: 2700) }
        let parts = spec.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts.allSatisfy({ (1...4000).contains($0) }),
              let context = CGContext(
                  data: nil, width: parts[0], height: parts[1], bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: parts[0], height: parts[1]))
        return context.makeImage().flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }

    private static func noise(width: Int, height: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        arc4random_buf(&bytes, bytes.count)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
#endif
