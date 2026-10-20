#if canImport(AppKit)
import AppKit
import Testing

/// Rendert eine View über `cacheDisplay` in ein sRGB-RGBA-Bild mit bekanntem Format.
@MainActor
struct Bitmap {
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

    struct Pixel { let r, g, b, a: Double }

    func pixel(_ x: Int, _ y: Int) -> Pixel {
        let p = rgba((y * width + x) * 4)
        return Pixel(r: p.r, g: p.g, b: p.b, a: p.a)
    }

    struct Box: Equatable { let minX, minY, maxX, maxY: Int
        var width: Int { maxX - minX + 1 }
        var height: Int { maxY - minY + 1 }
    }

    /// Kleinstes Rechteck um alle passenden Pixel (y nach unten), `nil` ohne Treffer.
    func boundingBox(where match: (Pixel) -> Bool) -> Box? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where match(pixel(x, y)) {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? nil : Box(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    /// Zeilen (y nach unten) mit mindestens einem passenden Pixel.
    func rows(where match: (Pixel) -> Bool) -> [Int] {
        (0..<height).filter { y in (0..<width).contains { match(pixel($0, y)) } }
    }

    /// Gleiche Pixel in den Zeilen `rows` (y nach unten) bei gleich großen Bildern.
    func rowsEqual(_ other: Bitmap, _ rows: Range<Int>) -> Bool {
        guard width == other.width, height == other.height else { return false }
        let clamped = rows.clamped(to: 0..<height)
        let range = (clamped.lowerBound * width * 4)..<(clamped.upperBound * width * 4)
        return pixels[range] == other.pixels[range]
    }

    func writePNG(named name: String) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "QuillEditorSnapshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try #require(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
        try data.write(to: directory.appending(path: "\(name).png"))
    }
}
#endif
