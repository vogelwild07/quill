// Zeigt die Typen auf der allgemeinen Zwischenablage (nur lesend).
// Aufruf: swift Scripts/pasteboard-types.swift [--preview]
// --preview zeigt zusätzlich die ersten 200 Zeichen textartiger Inhalte.
import AppKit

let preview = CommandLine.arguments.contains("--preview")
let pasteboard = NSPasteboard.general
let items = pasteboard.pasteboardItems ?? []
print("Änderungszähler: \(pasteboard.changeCount), Einträge: \(items.count)")
for (index, item) in items.enumerated() {
    print("Eintrag \(index + 1):")
    for type in item.types {
        let size = item.data(forType: type)?.count ?? 0
        print("  \(type.rawValue)  (\(size) Bytes)")
        if preview, let text = item.string(forType: type) {
            let snippet = text.prefix(200).replacingOccurrences(of: "\n", with: "⏎")
            print("    „\(snippet)\(text.count > 200 ? "…" : "")“")
        }
    }
}
