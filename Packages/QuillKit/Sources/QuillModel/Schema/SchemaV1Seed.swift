#if DEBUG
import Foundation
import SwiftData

/// Store im alten Format `SchemaV1`, um die Migration und die Rückfrage davor zu
/// testen (Phase 11.2). Nur im Debug-Build; nie für den echten Store.
public enum SchemaV1Seed {
    public static let rootTitle = "Projekte"
    public static let childTitle = "Quill"

    /// Legt an `storeURL` einen V1-Store mit zwei Seiten und einem Block an und merkt
    /// Version 1.0.0 vor, wie eine App vor V2 es getan hätte. Tut nichts, wenn dort
    /// schon ein Store liegt.
    public static func write(storeURL: URL, backupsURL: URL) throws {
        guard !FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)) else { return }
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Erst daneben anlegen, dann per `VACUUM INTO` als eine geschlossene Datei ohne
        // WAL ans Ziel: Sonst schreibt SQLite später noch zurück, und „unverändert“ ließe
        // sich nicht byte-genau prüfen.
        let scratch = FileManager.default.temporaryDirectory.appending(path: "QuillSeedV1-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let scratchStore = scratch.appending(path: storeURL.lastPathComponent)
        let schema = Schema(versionedSchema: SchemaV1.self)
        try autoreleasepool {
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: scratchStore, cloudKitDatabase: .none)
            )
            let context = ModelContext(container)
            let workspace = SchemaV1.Workspace()
            context.insert(workspace)
            let root = SchemaV1.Page(title: rootTitle, sortKey: "V")
            root.workspace = workspace
            let child = SchemaV1.Page(title: childTitle, sortKey: "V")
            child.workspace = workspace
            child.parent = root
            let block = SchemaV1.Block(kind: .todo, text: "Migration prüfen", sortKey: "V")
            block.isChecked = true
            block.page = child
            try context.save()
        }
        try StoreBackup.vacuum(scratchStore, into: storeURL)
        try StoreBackup(storeURL: storeURL, backupsURL: backupsURL, schemaVersion: "1.0.0").markOpened()
    }
}
#endif
