import AppKit

// Hintergrund für das Fenster der .dmg (640 × 400 pt), Entwurf „Tinte und Papier“:
// Schiefer aus Tinte, ein angedeutetes Blatt hinter dem Pfeil, unten ein Band in
// Petrol mit dem Satz zur Installation, Sonnengelb nur als kleiner Akzent.
//
// Aufruf: swift Scripts/dmg/background.swift <Ausgabe.tiff>
// Schreibt eine TIFF-Datei mit 1× und 2× (tiffutil -cathidpicheck). Der Hintergrund
// passt sich nicht an hell und dunkel an; der Finder schreibt die Namen unter den
// Icons im hellen Modus schwarz, im dunklen weiß. Die Fläche dahinter hat deshalb
// mittlere Helligkeit, und das Skript bricht ab, wenn eine der beiden Farben dort
// unter 4,5 : 1 fällt. Positionen müssen zu Scripts/dmg/settings.py passen.
let output = CommandLine.arguments.count == 2 ? CommandLine.arguments[1] : nil
guard let output else { print("Aufruf: swift Scripts/dmg/background.swift <Ausgabe.tiff>"); exit(2) }

let W: CGFloat = 640, H: CGFloat = 400
let iconSize: CGFloat = 128
let quillCenter = CGPoint(x: 160, y: 172), appsCenter = CGPoint(x: 480, y: 172)
/// Oberkante der Namen unter den Icons, wie der Finder sie bei 128 pt setzt.
let labelTop: CGFloat = quillCenter.y + iconSize / 2 + 6
let sentence = "Zum Installieren Quill in den Ordner „Programme“ ziehen."
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

let sun = hex(0xFFC23A), cream = hex(0xFFE7A8), paper = hex(0xF4EEE2), petrol = hex(0x0A5F5A)

/// Kontext mit Ursprung oben links, in Punkten.
func makeContext(scale: CGFloat) -> CGContext {
    let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: H * scale)
    ctx.scaleBy(x: scale, y: -scale)
    return ctx
}

func text(_ ctx: CGContext, _ string: String, size: CGFloat, color: CGColor, centerX: CGFloat, top: CGFloat) {
    let font = NSFont.systemFont(ofSize: size, weight: .medium)
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!, .kern: 0.1])
    let line = CTLineCreateWithAttributedString(attributed)
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    ctx.textPosition = CGPoint(x: centerX - width / 2, y: top + font.ascender)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

/// Blatt mit Eselsohr und drei Zeilen hinter dem Pfeil; endet über den Namen.
func sheet(_ ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: W / 2, y: 140)
    ctx.rotate(by: -0.07)
    let w: CGFloat = 150, h: CGFloat = 170, fold: CGFloat = 30
    let outline = CGMutablePath()
    outline.move(to: CGPoint(x: -w / 2, y: -h / 2))
    outline.addLine(to: CGPoint(x: w / 2 - fold, y: -h / 2))
    outline.addLine(to: CGPoint(x: w / 2, y: -h / 2 + fold))
    outline.addLine(to: CGPoint(x: w / 2, y: h / 2 - 50))
    outline.addLine(to: CGPoint(x: -w / 2, y: h / 2 - 50))
    outline.closeSubpath()
    ctx.addPath(outline)
    ctx.setFillColor(hex(0xFFFFFF, 0.06))
    ctx.fillPath()
    ctx.move(to: CGPoint(x: w / 2 - fold, y: -h / 2))
    ctx.addLine(to: CGPoint(x: w / 2 - fold, y: -h / 2 + fold))
    ctx.addLine(to: CGPoint(x: w / 2, y: -h / 2 + fold))
    ctx.setStrokeColor(hex(0xFFFFFF, 0.10))
    ctx.setLineWidth(1.2)
    ctx.strokePath()
    for i in 0..<3 {
        let y = -h / 2 + 50 + CGFloat(i) * 16
        ctx.move(to: CGPoint(x: -w / 2 + 20, y: y))
        ctx.addLine(to: CGPoint(x: w / 2 - 24 - CGFloat(i) * 18, y: y))
    }
    ctx.setStrokeColor(hex(0xFFFFFF, 0.07))
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

/// Gepunkteter Pfeil von Quill zu „Programme“ auf Höhe der Icon-Mitten.
func arrow(_ ctx: CGContext) {
    let start = CGPoint(x: quillCenter.x + iconSize / 2 + 22, y: quillCenter.y + 4)
    let end = CGPoint(x: appsCenter.x - iconSize / 2 - 26, y: appsCenter.y + 4)
    let control = CGPoint(x: (start.x + end.x) / 2, y: quillCenter.y - 30)
    ctx.saveGState()
    ctx.setStrokeColor(cream)
    ctx.setLineCap(.round)
    ctx.setLineWidth(4)
    ctx.setLineDash(phase: 0, lengths: [0.1, 9])
    ctx.move(to: start)
    ctx.addQuadCurve(to: end, control: control)
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    let angle = atan2(end.y - control.y, end.x - control.x)
    let length: CGFloat = 14, spread: CGFloat = 0.5
    ctx.setLineWidth(3)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread)))
    ctx.addLine(to: end)
    ctx.addLine(to: CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread)))
    ctx.strokePath()
    ctx.setFillColor(sun)
    ctx.fillEllipse(in: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10))
    ctx.restoreGState()
}

func draw(_ ctx: CGContext) {
    let gradient = CGGradient(colorsSpace: space, colors: [hex(0x6B8292), hex(0x617888), hex(0x617888)] as CFArray, locations: [0, 0.3, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: H), options: [])
    sheet(ctx)
    ctx.setFillColor(petrol)
    ctx.fill(CGRect(x: 0, y: 306, width: W, height: H - 306))
    ctx.setFillColor(sun)
    ctx.fill(CGRect(x: 0, y: 306, width: W, height: 1.5))
    arrow(ctx)
    text(ctx, sentence, size: 14, color: paper, centerX: W / 2, top: 342)
}

func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
    func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
}

let directory = FileManager.default.temporaryDirectory.appending(path: "QuillDmgBackground-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
var pngs: [String] = []
for scale in [CGFloat(1), 2] {
    let ctx = makeContext(scale: scale)
    draw(ctx)
    let image = ctx.makeImage()!
    // Kontrast unter beiden Namen für schwarze und weiße Schrift.
    let bytes = CFDataGetBytePtr(image.dataProvider!.data!)!
    var weakest = 21.0
    for center in [quillCenter, appsCenter] {
        for y in Int(labelTop * scale)..<Int((labelTop + 22) * scale) {
            for x in Int((center.x - 70) * scale)..<Int((center.x + 70) * scale) {
                let i = y * image.bytesPerRow + x * 4
                let l = luminance(Double(bytes[i]) / 255, Double(bytes[i + 1]) / 255, Double(bytes[i + 2]) / 255)
                weakest = min(weakest, 1.05 / (l + 0.05), (l + 0.05) / 0.05)
            }
        }
    }
    guard weakest >= 4.5 else { print("FEHLER: Namen nur \(String(format: "%.2f", weakest)) : 1 bei \(Int(scale))×"); exit(1) }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: W, height: H)
    let path = directory.appending(path: scale == 1 ? "background.png" : "background@2x.png").path
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    pngs.append(path)
    print("\(Int(scale))×: Namen schwarz und weiß mindestens \(String(format: "%.2f", weakest)) : 1")
}
// 2× als Retina-Ebene: Name mit @2x und 144 dpi, sonst behandelt tiffutil sie als
// doppelt so großes Bild statt als zweite Auflösung.
let sips = Process()
sips.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
sips.arguments = ["-s", "dpiWidth", "144", "-s", "dpiHeight", "144", pngs[1]]
sips.standardOutput = FileHandle.nullDevice
try sips.run()
sips.waitUntilExit()
guard sips.terminationStatus == 0 else { print("FEHLER: sips gescheitert"); exit(1) }
let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", pngs[0], pngs[1], "-out", output]
try tiffutil.run()
tiffutil.waitUntilExit()
guard tiffutil.terminationStatus == 0 else { print("FEHLER: tiffutil gescheitert"); exit(1) }
print("OK: \(output)")
