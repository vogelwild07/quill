#if QUILL_PROFILING
import AppKit
import OSLog
import QuillFeatures
import QuillModel

/// Testbestand für die Performance-UI-Tests, nur in der Konfiguration „Profiling“
/// (eigene Bundle-ID `io.github.vogelwild07.quill.profiling`, also eigener Sandbox-Container und
/// eigener Store). In Debug und Release ist dieser Code nicht enthalten;
/// `Scripts/check-release-binary.sh` prüft das (`docs/performance.md`).
///
/// `-QuillSeedPages N`: Store der Profiling-App vor dem Öffnen leeren, N Seiten mit je
/// 50 Blöcken anlegen (jede 50. mit Bild) und beenden. Gemessen wird erst danach.
enum ProfilingSeed {
    static let argument = "QuillSeedPages"
    static let bundleIdentifier = "io.github.vogelwild07.quill.profiling"
    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "profiling")

    /// Angeforderte Seitenzahl, nur in der Profiling-App und nur aus der Kommandozeile
    /// (nie aus gespeicherten Einstellungen, sonst leerte jeder Start den Store).
    static var requestedPages: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard Bundle.main.bundleIdentifier == bundleIdentifier,
              let index = arguments.firstIndex(of: "-\(argument)"),
              arguments.indices.contains(index + 1),
              let count = Int(arguments[index + 1]), count > 0
        else { return nil }
        return count
    }

    /// Vor dem Öffnen der Datenbank: `Quill/` im Container der Profiling-App leeren.
    static func resetStoreIfRequested() {
        guard requestedPages != nil else { return }
        let directory = QuillStore.directoryURL
        // Doppelte Sicherung: nur innerhalb des eigenen Containers.
        guard directory.path(percentEncoded: false).contains("/Containers/\(bundleIdentifier)/") else {
            fatalError("Profiling-Store liegt nicht im eigenen Container: \(directory.path(percentEncoded: false))")
        }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Legt den Bestand an und beendet die App.
    @MainActor
    static func seedAndQuit(_ persistence: QuillPersistence) {
        guard let count = requestedPages else { return }
        // Der Text steht so auch im Binary; Swift legt kurze Zeichenketten wie
        // `argument` nicht als Text ab. `Scripts/check-release-binary.sh` sucht ihn.
        logger.notice("Profiling-Bestand (-QuillSeedPages): \(count) Seiten")
        let store = persistence.store
        let image = makeImage()
        Task {
            do {
                try await seed(count: count, store: store, image: image)
            } catch {
                fatalError("Seed fehlgeschlagen: \(error)")
            }
            NSApp.terminate(nil)
        }
    }

    /// Wurzeln sind jede zehnte Seite, darunter je vier Kinder mit je einem Enkel.
    private static func seed(count: Int, store: PageStore, image: Data) async throws {
        var root: UUID?
        var child: UUID?
        for index in 0..<count {
            let parent: UUID? = switch index % 10 {
            case 0: nil
            case 1, 3, 5, 7: root
            default: child
            }
            let id = try await store.createPage(title: "Seite \(index)", in: parent)
            switch index % 10 {
            case 0: root = id
            case 1, 3, 5, 7: child = id
            default: break
            }
            var blocks = (0..<50).map { block(page: index, number: $0) }
            if index % 50 == 0 {
                let imageBlock = BlockSnapshot(id: UUID(), kindRaw: BlockKind.image.rawValue)
                blocks.insert(imageBlock, at: 3)
                try await store.applyEdits(id, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
                _ = try await store.importImage(image, linkTo: imageBlock.id)
            } else {
                try await store.applyEdits(id, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
            }
        }
    }

    private static func block(page: Int, number: Int) -> BlockSnapshot {
        let text = "Seite \(page), Absatz \(number): Quill speichert lokal, startet schnell und hält den Text im Mittelpunkt."
        let kind: BlockKind = switch number % 10 {
        case 0: .heading2
        case 4: .bulleted
        case 5: .todo
        case 8: .quote
        default: .paragraph
        }
        return BlockSnapshot(id: UUID(), kindRaw: kind.rawValue, text: text)
    }

    /// Farbverlauf als PNG, 1600 × 1000.
    @MainActor
    private static func makeImage() -> Data {
        let size = NSSize(width: 1600, height: 1000)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: .systemBlue, ending: .systemTeal)?.draw(in: rect, angle: 30)
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { fatalError("Testbild nicht erzeugt") }
        return png
    }
}
#endif
