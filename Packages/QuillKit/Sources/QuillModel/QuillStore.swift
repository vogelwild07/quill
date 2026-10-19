import Foundation
import SwiftData

/// Erzeugt den `ModelContainer` von Quill mit festem Speicherort.
///
/// Der feste Ort (statt des SwiftData-Standards) ist nötig, damit Backups die
/// Datei finden. CloudKit bleibt aus, bis Sync kommt (ADR-005).
public enum QuillStore {
    /// Ordner `Application Support/Quill` im Sandbox-Container.
    public static var directoryURL: URL {
        URL.applicationSupportDirectory.appending(path: "Quill", directoryHint: .isDirectory)
    }

    /// `Application Support/Quill/Store/Quill.store`. Alle Dateien des Stores liegen
    /// in `Store/`, damit das Wiederherstellen den Ordner in einem Schritt tauschen
    /// kann (ADR-019). Bis Phase 7.1 lagen sie direkt in `Quill/`; `StoreBackup`
    /// zieht sie beim Start einmal um.
    public static var defaultStoreURL: URL {
        directoryURL.appending(path: "Store/Quill.store", directoryHint: .notDirectory)
    }

    public static var schema: Schema {
        Schema(versionedSchema: CurrentSchema.self)
    }

    /// Version des aktuellen Schemas, z. B. `"1.0.0"`.
    public static var schemaVersion: String {
        let version = CurrentSchema.versionIdentifier
        return "\(version.major).\(version.minor).\(version.patch)"
    }

    /// Container auf der Festplatte; legt den Ordner bei Bedarf an.
    public static func makeContainer(storeURL: URL = defaultStoreURL) throws -> ModelContainer {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(
            for: schema,
            migrationPlan: QuillMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// Container nur im Arbeitsspeicher, für Tests, Previews und UI-Tests.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: QuillMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
