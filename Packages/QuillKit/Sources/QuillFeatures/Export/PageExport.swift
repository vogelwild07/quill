#if canImport(AppKit)
import AppKit
import OSLog
import QuillExport
import QuillModel

/// „Exportieren …“ (ADR-018): Ordner wählen, Seite (mit Unterseiten) als Markdown
/// schreiben, Ergebnis melden. Das Schreiben läuft im Hintergrund.
@MainActor
enum PageExport {
    /// UI-Tests: Export ohne Dialog in diesen Unterordner des temporären Ordners der
    /// App (in der Sandbox der einzige ohne Rückfrage beschreibbare Ort), immer mit
    /// Unterseiten. Nie ein Pfad von außen.
    static let directoryArgument = "QuillExportDirectory"

    private static let logger = Logger(subsystem: "de.vogel.quill", category: "export")

    static func run(pageID: UUID, title: String, store: PageStore, window: NSWindow?, defaults: UserDefaults = .standard) {
        if let name = defaults.string(forKey: directoryArgument), !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") {
            let folder = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            write(pageID: pageID, title: title, includeSubpages: true, into: folder, store: store, window: window)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Exportieren", bundle: .module)
        panel.message = String(localized: "Ordner für den Export von „\(PageLabel.title(title))“ wählen", bundle: .module)
        let subpages = NSButton(checkboxWithTitle: String(localized: "Unterseiten einschließen", bundle: .module), target: nil, action: nil)
        subpages.state = .on
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: subpages.fittingSize.width + 40, height: subpages.fittingSize.height + 16))
        subpages.frame.origin = NSPoint(x: 20, y: 8)
        accessory.addSubview(subpages)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            write(pageID: pageID, title: title, includeSubpages: subpages.state == .on, into: url, store: store, window: window)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private static func write(pageID: UUID, title: String, includeSubpages: Bool, into destination: URL, store: PageStore, window: NSWindow?) {
        let strings = ExportStrings(
            untitled: String(localized: "Ohne Titel", bundle: .module),
            subpages: String(localized: "Unterseiten", bundle: .module),
            missingImage: String(localized: "Bild fehlt", bundle: .module)
        )
        Task {
            let accessing = destination.startAccessingSecurityScopedResource()
            defer { if accessing { destination.stopAccessingSecurityScopedResource() } }
            do {
                let snapshot = try await store.exportSnapshot(of: pageID, includeSubpages: includeSubpages)
                let result = try await ExportWriter.export(
                    snapshot, strings: strings, into: destination,
                    imageData: { try await store.imageData($0)?.data }
                )
                report(result, title: PageLabel.title(snapshot.title), window: window)
            } catch {
                // Fehlertexte enthalten Pfade und Seitentitel: nicht öffentlich protokollieren.
                logger.error("Export fehlgeschlagen: \(error, privacy: .private)")
                fail(error, window: window)
            }
        }
    }

    private static func report(_ result: ExportResult, title: String, window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = String(localized: "„\(title)“ exportiert", bundle: .module)
        var lines = [
            String(localized: "Seiten: \(result.pageCount) · Bilder: \(result.imageCount)", bundle: .module),
            String(localized: "Ordner: \(result.folder.lastPathComponent)", bundle: .module),
        ]
        if result.missingImageCount > 0 {
            lines.append(String(localized: "Fehlende Bilder: \(result.missingImageCount)", bundle: .module))
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: String(localized: "OK", bundle: .module))
        alert.addButton(withTitle: String(localized: "Im Finder zeigen", bundle: .module))
        show(alert, in: window) { response in
            if response == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([result.folder])
            }
        }
    }

    private static func fail(_ error: any Error, window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Export fehlgeschlagen", bundle: .module)
        alert.informativeText = error.localizedDescription
        show(alert, in: window) { _ in }
    }

    private static func show(_ alert: NSAlert, in window: NSWindow?, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}
#endif
