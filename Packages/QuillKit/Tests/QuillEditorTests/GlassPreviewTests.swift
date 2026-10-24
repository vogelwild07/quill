#if canImport(AppKit)
import AppKit
import CoreImage
@testable import QuillEditorCore
import QuillTestFixtures
import Testing

/// Vorschaubilder der Sidebar mit dem Glas von Quill (ADR-036): klar, Mitte und getönt,
/// je hell und dunkel, jeweils über hellem, dunklem und buntem Hintergrund.
///
/// Echtes Glas setzt erst der Fenster-Server zusammen; `ImageRenderer` und
/// `cacheDisplay` zeigen es nicht, Bildschirmaufnahmen sind ausgeschlossen. Die Bilder
/// sind deshalb eine gerechnete Näherung: Hintergrund mit Unschärfe, darüber die Fläche
/// in der Theme-Farbe mit der Deckkraft der Stufe, darauf Text in den Farben des Glases.
/// Ablage in `QUILL_GLASS_PREVIEW_DIR` (`Design/Vorschau/`), sonst in
/// `$TMPDIR/QuillGlassPreview`.
@MainActor
@Suite("Liquid Glass: Vorschaubilder", .serialized, .renderingLock)
struct GlassPreviewTests {
    static let levels: [(name: String, level: Double)] = [("klar", 0), ("mitte", 0.5), ("getoent", 1)]
    static let panel = CGSize(width: 240, height: 340)
    static let gap: CGFloat = 20
    static let caption: CGFloat = 44

    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["QUILL_GLASS_PREVIEW_DIR"], !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return FileManager.default.temporaryDirectory.appending(path: "QuillGlassPreview", directoryHint: .isDirectory)
    }

    @Test(arguments: [false, true])
    func sidebarPreviews(dark: Bool) throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let tint = GlassTint(theme: .standard, dark: dark, increaseContrast: false)
        for (name, level) in Self.levels {
            let opacity = tint.opacity(level: level, reduceTransparency: false)
            let image = try Self.render(tint: tint, opacity: opacity, title: Self.title(level: name, dark: dark, opacity: opacity))
            let url = Self.directory.appending(path: "liquid-glass-sidebar-\(name)-\(dark ? "dunkel" : "hell").png")
            try image.write(to: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    static func title(level: String, dark: Bool, opacity: Double) -> String {
        let stufe = ["klar": "klar", "mitte": "Mitte", "getoent": "getönt"][level] ?? level
        return "Sidebar, Theme Standard, \(stufe), \(dark ? "dunkel" : "hell"), Deckkraft \(Int((opacity * 100).rounded())) %"
            + " – gerechnete Näherung, kein Bildschirmfoto"
    }

    /// Drei Felder nebeneinander: Sidebar über hellem, dunklem und buntem Hintergrund.
    static func render(tint: GlassTint, opacity: Double, title: String) throws -> Data {
        let width = 3 * panel.width + 4 * gap
        let height = panel.height + 2 * gap + caption
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )?.retagging(with: .sRGB))
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: width, height: height).fill()
        for (index, backdrop) in Backdrop.allCases.enumerated() {
            let frame = CGRect(x: gap + CGFloat(index) * (panel.width + gap), y: caption + gap, width: panel.width, height: panel.height)
            drawBackdrop(backdrop, in: frame.insetBy(dx: -gap / 2, dy: -gap / 2), panel: frame)
            drawSidebar(tint: tint, opacity: opacity, in: frame)
            label(backdrop.name, at: CGPoint(x: frame.minX, y: caption - 18), color: .black, size: 11)
        }
        label(title, at: CGPoint(x: gap, y: 6), color: .black, size: 11)
        context.flushGraphics()
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    enum Backdrop: CaseIterable {
        case light, dark, colorful

        var name: String {
            switch self {
            case .light: "über hellem Hintergrund"
            case .dark: "über dunklem Hintergrund"
            case .colorful: "über buntem Hintergrund"
            }
        }
    }

    /// Hintergrund im ganzen Feld, unter der Sidebar unscharf wie hinter Glas.
    static func drawBackdrop(_ backdrop: Backdrop, in frame: CGRect, panel: CGRect) {
        let image = NSImage(size: frame.size, flipped: false) { rect in
            switch backdrop {
            case .light:
                NSColor(srgbRed: 0.96, green: 0.96, blue: 0.95, alpha: 1).setFill()
                rect.fill()
                NSColor(srgbRed: 0.82, green: 0.84, blue: 0.86, alpha: 1).setFill()
                for row in stride(from: 0, to: rect.height, by: 36) { CGRect(x: 0, y: row, width: rect.width, height: 12).fill() }
            case .dark:
                NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1).setFill()
                rect.fill()
                NSColor(srgbRed: 0.22, green: 0.24, blue: 0.28, alpha: 1).setFill()
                for row in stride(from: 0, to: rect.height, by: 36) { CGRect(x: 0, y: row, width: rect.width, height: 12).fill() }
            case .colorful:
                let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .systemOrange]
                for (index, color) in colors.enumerated() {
                    color.setFill()
                    let band = rect.height / CGFloat(colors.count)
                    CGRect(x: 0, y: CGFloat(index) * band, width: rect.width, height: band).fill()
                }
                NSColor.white.setFill()
                NSBezierPath(ovalIn: CGRect(x: rect.width * 0.55, y: rect.height * 0.55, width: 90, height: 90)).fill()
            }
            return true
        }
        image.draw(in: frame)
        // Unschärfe nur unter der Sidebar, wie hinter Glas.
        guard let tiff = image.tiffRepresentation, let input = CIImage(data: tiff) else { return }
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 10).cropped(to: input.extent)
        let local = CGRect(x: panel.minX - frame.minX, y: panel.minY - frame.minY, width: panel.width, height: panel.height)
        let scale = input.extent.width / frame.width
        let source = CGRect(x: local.minX * scale, y: local.minY * scale, width: local.width * scale, height: local.height * scale)
        let rendered = NSCIImageRep(ciImage: blurred.cropped(to: source))
        let result = NSImage(size: panel.size)
        result.addRepresentation(rendered)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: panel, xRadius: 14, yRadius: 14).addClip()
        result.draw(in: panel)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Fläche in der Theme-Farbe mit der Deckkraft der Stufe, darauf Zeilen der Sidebar.
    static func drawSidebar(tint: GlassTint, opacity: Double, in frame: CGRect) {
        let shape = NSBezierPath(roundedRect: frame, xRadius: 14, yRadius: 14)
        NSColor(tint.color).withAlphaComponent(opacity).setFill()
        shape.fill()
        let text = NSColor(tint.text)
        let secondary = NSColor(tint.secondary)
        let rows: [(String, NSColor, CGFloat, Bool)] = [
            ("Suchen    ⌘O", secondary, 16, false),
            ("Favoriten", secondary, 16, true),
            ("Einkaufsliste", text, 28, false),
            ("Seiten", secondary, 16, true),
            ("Projekt Quill", text, 28, false),
            ("Notizen", text, 44, false),
            ("Reise nach Lissabon", text, 28, false),
            ("Tage", text, 28, false),
            ("+ Neue Seite", secondary, 16, false),
            ("Papierkorb", secondary, 16, false),
        ]
        var y = frame.maxY - 34
        for (title, color, indent, isGroup) in rows {
            label(title, at: CGPoint(x: frame.minX + indent, y: y), color: color, size: isGroup ? 11 : 13, bold: isGroup)
            y -= 30
        }
    }

    static func label(_ string: String, at point: CGPoint, color: NSColor, size: CGFloat, bold: Bool = false) {
        let font = bold ? NSFont.systemFont(ofSize: size, weight: .semibold) : NSFont.systemFont(ofSize: size)
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]).draw(at: point)
    }
}

private extension NSColor {
    convenience init(_ value: SRGB) {
        self.init(srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
    }
}
#endif
