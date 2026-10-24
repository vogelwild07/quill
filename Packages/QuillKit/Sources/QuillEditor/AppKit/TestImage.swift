#if canImport(AppKit) && (DEBUG || QUILL_SYNCTEST)
import AppKit
import OSLog
import QuillEditorCore

/// Startargument `-QuillTestImage <Breite>x<Höhe>`, `heavy`, `demo` oder `text`:
/// Die App erzeugt das Testbild selbst und legt es in ihre eigene Zwischenablage
/// (`-QuillPasteboardName`). So setzen UI-Tests Bilder ein, ohne dass ein anderer
/// Prozess die Zwischenablage füllt; das sperrt der Datenschutz („Einsetzen aus
/// anderen Apps“). Nur im Debug-Build und in den Testvarianten Synctest A und B,
/// nur aus der Kommandozeile, nie in die allgemeine Zwischenablage.
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

    /// `heavy`: Rauschen, kaum komprimierbar, ein PNG über 20 MB. `demo`: ruhige
    /// Landschaft für die Bilder in der README (`ReadmeScreenshotUITests`). Sonst
    /// einfarbig in `<Breite>x<Höhe>` (je 1…4000). `text`: dunkle Schrift auf Weiß für
    /// die Texterkennung (ADR-034).
    static func png(spec: String) -> Data? {
        if spec == "heavy" { return noise(width: 2700, height: 2700) }
        if spec == "demo" { return landscape(width: 1600, height: 640) }
        if spec == "text" { return lettering(textImageText, width: 800, height: 200) }
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

    /// Himmel als Verlauf, Sonne und zwei Hügelketten; selbst gezeichnet, ohne
    /// fremde Vorlage.
    private static func landscape(width: Int, height: Int) -> Data? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ),
              let sky = CGGradient(colorsSpace: space, colors: [
                  CGColor(srgbRed: 0.98, green: 0.80, blue: 0.62, alpha: 1),
                  CGColor(srgbRed: 0.55, green: 0.70, blue: 0.92, alpha: 1),
              ] as CFArray, locations: [0, 1]) else { return nil }
        let w = CGFloat(width), h = CGFloat(height)
        // CoreGraphics zählt y von unten: Verlauf vom Horizont nach oben.
        context.drawLinearGradient(sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])
        context.setFillColor(CGColor(srgbRed: 1, green: 0.93, blue: 0.75, alpha: 1))
        context.fillEllipse(in: CGRect(x: w * 0.68, y: h * 0.42, width: h * 0.28, height: h * 0.28))
        func hills(base: CGFloat, amplitude: CGFloat, phase: CGFloat, color: CGColor) {
            context.move(to: CGPoint(x: 0, y: 0))
            for x in stride(from: CGFloat(0), through: w, by: 8) {
                let y = h * base + h * amplitude * sin(x / w * .pi * 2.2 + phase)
                context.addLine(to: CGPoint(x: x, y: y))
            }
            context.addLine(to: CGPoint(x: w, y: 0))
            context.closePath()
            context.setFillColor(color)
            context.fillPath()
        }
        hills(base: 0.38, amplitude: 0.07, phase: 0.6, color: CGColor(srgbRed: 0.42, green: 0.58, blue: 0.66, alpha: 1))
        hills(base: 0.22, amplitude: 0.06, phase: 2.4, color: CGColor(srgbRed: 0.27, green: 0.45, blue: 0.47, alpha: 1))
        return context.makeImage().flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }

    /// Text im Bild `text`, den UI-Tests in der Suche finden.
    static let textImageText = "Fahrplan Gardasee"

    private static func lettering(_ text: String, width: Int, height: Int) -> Data? {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            (text as NSString).draw(
                at: NSPoint(x: 40, y: CGFloat(height) / 2 - 24),
                withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black]
            )
            return true
        }
        return image.tiffRepresentation
            .flatMap(NSBitmapImageRep.init(data:))
            .flatMap { $0.representation(using: .png, properties: [:]) }
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
