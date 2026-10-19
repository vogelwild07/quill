#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import QuillFeatures

/// Leerzustände, Speicherhinweis und Fehleransicht hell und dunkel aus der App
/// selbst gerendert (keine Bildschirmfotos). Prüfregeln statt Referenzbildern:
/// Text hebt sich mit WCAG-Kontrast 4.5:1 vom Hintergrund ab, hell gibt es dunklen
/// Text, und im Dunkeln ist nichts dunkler als der Hintergrund (eine feste Farbe
/// wie Schwarz fiele auf).
/// PNGs zur Sichtkontrolle in `$TMPDIR/QuillEditorSnapshots`.
@MainActor
@Suite("Leerzustände: Darstellung hell und dunkel", .serialized)
struct EmptyStateSnapshotTests {
    nonisolated static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    @Test(arguments: EmptyState.allCases, appearances)
    func emptyStateIsLegible(_ state: EmptyState, _ appearance: NSAppearance.Name) throws {
        let view = EmptyStateView(state, id: "test", actionTitle: state == .noSelection ? "Neue Seite" : nil, action: {})
        let image = try Snapshot(view, size: CGSize(width: 420, height: 320), appearance: appearance)
        try image.writePNG(named: "empty-\(state)-\(appearance.rawValue)")
        try expectSystemColors(image, appearance: appearance)
        #expect(image.strongestContrast >= 4.5, "Titel kaum lesbar: \(image.strongestContrast)")
    }

    /// Befund A14: Hinweis „Nicht gespeichert“ auf der Kapsel (quaternary).
    @Test(arguments: appearances)
    func saveProblemBadgeIsLegible(_ appearance: NSAppearance.Name) throws {
        let badge = SaveProblemBadge(error: CocoaError(.fileWriteNoPermission)).padding(8)
        let image = try Snapshot(badge, size: CGSize(width: 160, height: 40), appearance: appearance)
        try image.writePNG(named: "save-problem-\(appearance.rawValue)")
        try expectSystemColors(image, appearance: appearance)
        // Gegen die Kapsel, nicht gegen das Fenster: links innen, vor dem Symbol.
        let capsule = image.luminance(atX: 8 + 5, y: image.height / 2)
        #expect(image.strongestContrast(against: capsule) >= 4.5, "Text auf der Kapsel kaum lesbar: \(image.strongestContrast(against: capsule))")
    }

    /// Befund A14: Ansicht, wenn sich die Datenbank nicht öffnen lässt.
    @Test(arguments: appearances)
    func persistenceErrorIsLegible(_ appearance: NSAppearance.Name) throws {
        let view = PersistenceErrorView(error: CocoaError(.fileReadCorruptFile))
        let image = try Snapshot(view, size: CGSize(width: 480, height: 320), appearance: appearance)
        try image.writePNG(named: "persistence-error-\(appearance.rawValue)")
        try expectSystemColors(image, appearance: appearance)
        #expect(image.strongestContrast >= 4.5, "Titel kaum lesbar: \(image.strongestContrast)")
    }

    private func expectSystemColors(_ image: Snapshot, appearance: NSAppearance.Name) throws {
        // Helligkeit im Gamma-Raum: Linear lägen Dunkelgrau und Schwarz fast gleich.
        if appearance == .darkAqua {
            #expect(image.minimumBrightness >= image.backgroundBrightness - 0.02, "Fest dunkle Farbe im Dunkelmodus")
        } else {
            // Text dunkler als der Hintergrund (Knöpfe dürfen heller sein).
            #expect(image.minimumBrightness < image.backgroundBrightness - 0.3, "Kein dunkler Text im Hellmodus")
        }
    }
}

/// Gerenderte Ansicht mit undurchsichtigem Fensterhintergrund.
@MainActor
private struct Snapshot {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    let cgImage: CGImage

    init(_ view: some View, size: CGSize, appearance: NSAppearance.Name) throws {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let hosting = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let source = try #require(rep.cgImage)
        width = source.width
        height = source.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let (w, h) = (width, height)
        buffer.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        pixels = buffer
        cgImage = source
    }

    /// Relative Leuchtdichte nach WCAG (linearisiertes sRGB).
    private func luminance(_ index: Int) -> Double {
        func linear(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(pixels[index]) + 0.7152 * linear(pixels[index + 1]) + 0.0722 * linear(pixels[index + 2])
    }

    func luminance(atX x: Int, y: Int) -> Double { luminance((y * width + x) * 4) }

    /// Fensterhintergrund: Ecke unten rechts.
    var background: Double { luminance(atX: width - 2, y: height - 2) }

    /// Helligkeit im Gamma-Raum (ohne Linearisierung), für den Vergleich mit dem Hintergrund.
    private func brightness(_ index: Int) -> Double {
        (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])) / 255
    }

    var backgroundBrightness: Double { brightness(((height - 2) * width + width - 2) * 4) }

    var minimumBrightness: Double { stride(from: 0, to: pixels.count, by: 4).map(brightness).min() ?? 0 }

    /// Größter Kontrast eines Pixels gegen eine Leuchtdichte (WCAG-Verhältnis).
    func strongestContrast(against reference: Double) -> Double {
        stride(from: 0, to: pixels.count, by: 4).map { index in
            let l = luminance(index)
            return (max(l, reference) + 0.05) / (min(l, reference) + 0.05)
        }.max() ?? 1
    }

    var strongestContrast: Double { strongestContrast(against: background) }

    func writePNG(named name: String) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "QuillEditorSnapshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try #require(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
        try data.write(to: directory.appending(path: "\(name).png"))
    }
}
#endif
