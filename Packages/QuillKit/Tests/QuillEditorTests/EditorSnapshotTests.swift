#if canImport(AppKit)
import AppKit
import Testing
@testable import QuillEditor

/// Rendert den Editor hell und dunkel aus der App selbst (keine Bildschirmfotos)
/// und prüft, dass selbst gezeichnete Elemente Systemfarben nutzen.
/// Die PNGs landen in `$TMPDIR/QuillEditorSnapshots` zur Sichtkontrolle; ersetzt
/// `-snapshot` des gelöschten Editor-Spikes.
@MainActor
@Suite("Editor: Darstellung hell und dunkel", .serialized)
struct EditorSnapshotTests {
    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func editorUsesSystemColors(_ appearance: NSAppearance.Name) throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let editor = BlockEditorController(document: SampleDocuments.welcome)
        window.contentView = editor.scrollView
        editor.textView.layoutSubtreeIfNeeded()
        let firstLine = editor.textView.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
        let point = editor.textView.convert(window.convertPoint(fromScreen: firstLine.origin), from: nil)
        editor.textView.updateHandle(for: CGPoint(x: 100, y: point.y - 4))
        #expect(!editor.textView.handle.isHidden)

        let view = try #require(window.contentView)
        let image = try Bitmap(view)
        try image.writePNG(named: "editor-\(appearance.rawValue)")

        let background = image.luminance(atX: image.width - 4, y: image.height - 4)
        if appearance == .darkAqua {
            // Fest schwarz gezeichnete Elemente wären dunkler als der Hintergrund.
            #expect(image.minimumLuminance >= background - 0.02)
        } else {
            #expect(image.maximumLuminance <= background + 0.02)
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func handleUsesTertiaryAndOnHoverSecondaryLabel(_ appearance: NSAppearance.Name) throws {
        let handle = BlockHandleView(frame: CGRect(x: 0, y: 0, width: 20, height: 22))
        handle.appearance = NSAppearance(named: appearance)

        let normal = try Bitmap(handle)
        handle.isHovered = true
        let hovered = try Bitmap(handle)
        try hovered.writePNG(named: "handle-hover-\(appearance.rawValue)")

        let dark = appearance == .darkAqua
        // Punkte erscheinen hell auf dunkel bzw. dunkel auf hell …
        #expect(dark ? normal.strongestDot.brightness > 0.8 : normal.strongestDot.brightness < 0.2)
        // … und bei Hover deckender.
        #expect(hovered.strongestDot.alpha > normal.strongestDot.alpha + 0.1)
        // Sechs Punkte (⋮⋮), nicht drei Striche (≡).
        #expect(normal.dotCount == 6)
    }
}

/// Rendert eine View über `cacheDisplay` in ein sRGB-RGBA-Bild mit bekanntem Format.
@MainActor
private struct Bitmap {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    let cgImage: CGImage

    init(_ view: NSView) throws {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let source = try #require(rep.cgImage)
        let width = source.width, height = source.height
        self.width = width
        self.height = height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        buffer.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        pixels = buffer
        cgImage = source
    }

    private func rgba(_ index: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        let a = Double(pixels[index + 3]) / 255
        guard a > 0 else { return (0, 0, 0, 0) }
        return (Double(pixels[index]) / 255 / a, Double(pixels[index + 1]) / 255 / a, Double(pixels[index + 2]) / 255 / a, a)
    }

    private func luminance(_ index: Int) -> Double {
        let p = rgba(index)
        return 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
    }

    func luminance(atX x: Int, y: Int) -> Double { luminance((y * width + x) * 4) }

    var minimumLuminance: Double { stride(from: 0, to: pixels.count, by: 4).map(luminance).min() ?? 0 }
    var maximumLuminance: Double { stride(from: 0, to: pixels.count, by: 4).map(luminance).max() ?? 0 }

    /// Deckendster Pixel: Farbe und Deckkraft eines Griff-Punkts.
    var strongestDot: (brightness: Double, alpha: Double) {
        let index = stride(from: 0, to: pixels.count, by: 4).max { pixels[$0 + 3] < pixels[$1 + 3] } ?? 0
        return (luminance(index), rgba(index).a)
    }

    /// Zusammenhängende sichtbare Flächen (4er-Nachbarschaft).
    var dotCount: Int {
        var seen = [Bool](repeating: false, count: width * height)
        var count = 0
        for start in 0..<(width * height) where !seen[start] && pixels[start * 4 + 3] > 40 {
            count += 1
            var stack = [start]
            seen[start] = true
            while let pixel = stack.popLast() {
                let x = pixel % width, y = pixel / width
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < width && ny < height {
                    let next = ny * width + nx
                    if !seen[next] && pixels[next * 4 + 3] > 40 {
                        seen[next] = true
                        stack.append(next)
                    }
                }
            }
        }
        return count
    }

    func writePNG(named name: String) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "QuillEditorSnapshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try #require(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
        try data.write(to: directory.appending(path: "\(name).png"))
    }
}
#endif
