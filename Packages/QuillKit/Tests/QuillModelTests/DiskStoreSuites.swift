import Foundation
import Testing

/// Suiten mit Stores samt Bildern auf der Platte laufen nacheinander, nicht parallel
/// zueinander. Vorsicht, keine bewiesene Ursache: Zweimal las ein Test bei parallelem
/// Lauf Bildbytes, die nur in einer anderen Suite vorkommen. In Phase 7.2 einmal in 50
/// Läufen ohne Serialisierung nachgestellt: Die Datei auf der Platte war richtig, falsch
/// war nur, was gelesen wurde (ADR-019). Die Bild-Assertions nennen deshalb bei einem
/// Fehlschlag Store-Pfad und externe Dateien.
@Suite(.serialized) enum DiskStoreSuites {
    /// Prüft die ersten Bytes aller Bilder eines Stores und nennt bei Abweichung den
    /// Store-Pfad und die Dateien in `.Quill_SUPPORT` mit Größe und erstem Byte.
    static func expectImageBytes(
        _ actual: [UInt8], _ expected: [UInt8], store: URL, _ note: String = "",
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard actual != expected else { return }
        Issue.record(
            "\(note) Bilder \(actual) statt \(expected). Store: \(store.path(percentEncoded: false)). Externe Dateien: \(externalFiles(of: store))",
            sourceLocation: sourceLocation
        )
    }

    /// Dateien in `.<Name>_SUPPORT` neben dem Store, relativ, mit Größe und erstem Byte.
    static func externalFiles(of store: URL) -> [String] {
        let support = store.deletingLastPathComponent()
            .appending(path: ".\(store.deletingPathExtension().lastPathComponent)_SUPPORT", directoryHint: .isDirectory)
        guard let enumerator = FileManager.default.enumerator(at: support, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return ["kein \(support.lastPathComponent)"]
        }
        var result: [String] = []
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let data = (try? Data(contentsOf: url)) ?? Data()
            // Ohne Symlinks vergleichen: /var ist /private/var.
            let base = support.resolvingSymlinksInPath().path(percentEncoded: false)
            let relative = url.resolvingSymlinksInPath().path(percentEncoded: false).replacingOccurrences(of: base, with: "")
            result.append("\(relative) (\(data.count) B, erstes Byte \(data.first.map(String.init) ?? "-"))")
        }
        return result.sorted()
    }
}
