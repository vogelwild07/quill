import Foundation
import SwiftData
import Testing
@testable import QuillModel

extension DiskStoreSuites {
    /// Migrationstests (ADR-011).
    ///
    /// - `v1ToV2`: Ein mit `SchemaV1` befüllter Store öffnet mit dem echten
    ///   `QuillMigrationPlan` als V2 ohne Datenverlust; die Sync-Felder sind leer.
    /// - `rehearsalV2ToV3`: Probelauf der Kette mit einer `SchemaV3` nur im Test und
    ///   eigener Stufe, inklusive Backup vor der Migration.
    ///
    /// Bei jeder echten neuen Version kommt ein Test „V(n-1) → V(n)“ dazu.
    @Suite struct MigrationTests {
        let directory: URL
        let storeURL: URL

        init() {
            directory = URL.temporaryDirectory.appending(path: "QuillMigrationTests-\(UUID().uuidString)")
            storeURL = directory.appending(path: "Quill.store")
        }

        /// Store mit explizit `SchemaV1` anlegen: Baum, Blöcke mit Bild, Papierkorb, Favorit.
        private func makeV1Store() throws -> Fixture {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            )
            let context = ModelContext(container)
            let workspace = SchemaV1.Workspace()
            context.insert(workspace)

            let root = SchemaV1.Page(title: "Projekte", sortKey: "V")
            root.icon = "📁"
            root.workspace = workspace
            root.isFavorite = true
            root.favoriteSortKey = "V"
            let child = SchemaV1.Page(title: "Quill", sortKey: "V")
            child.workspace = workspace
            child.parent = root
            let trashed = SchemaV1.Page(title: "Alt", sortKey: "W")
            trashed.workspace = workspace
            trashed.trashedAt = Date(timeIntervalSince1970: 1_800_000_000)

            let heading = SchemaV1.Block(kind: .heading1, text: "Ziele", sortKey: "V")
            heading.page = child
            let todo = SchemaV1.Block(kind: .todo, text: "Spike", sortKey: "W")
            todo.isChecked = true
            todo.indent = 1
            todo.page = child
            let image = SchemaV1.Block(kind: .image, sortKey: "X")
            image.page = child
            image.asset = SchemaV1.Asset(data: Data(repeating: 9, count: 200_000))
            try context.save()

            return Fixture(rootID: root.id, childID: child.id, trashedID: trashed.id)
        }

        struct Fixture {
            let rootID: UUID
            let childID: UUID
            let trashedID: UUID
        }

        @Test func v1ToV2() throws {
            defer { try? FileManager.default.removeItem(at: directory) }
            let fixture = try makeV1Store()

            let container = try QuillStore.makeContainer(storeURL: storeURL)

            let context = ModelContext(container)
            let pages = try context.fetch(FetchDescriptor<Page>())
            #expect(pages.count == 3)
            #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 1)
            let root = try #require(pages.first { $0.id == fixture.rootID })
            let child = try #require(pages.first { $0.id == fixture.childID })
            let trashed = try #require(pages.first { $0.id == fixture.trashedID })
            #expect(root.icon == "📁")
            #expect(root.isFavorite && root.favoriteSortKey == "V")
            #expect(child.parent?.id == root.id)
            #expect(trashed.trashedAt == Date(timeIntervalSince1970: 1_800_000_000))
            let blocks = (child.blocks ?? []).sorted { $0.sortKey < $1.sortKey }
            #expect(blocks.map(\.kind) == [.heading1, .todo, .image])
            #expect(blocks[1].isChecked && blocks[1].indent == 1)
            #expect(blocks[2].asset?.data?.count == 200_000)
            // Neue Felder aus V2: leer bzw. `false`.
            #expect(pages.allSatisfy { $0.syncDocument == nil && !$0.isRestored })
            #expect(blocks.allSatisfy { !$0.isRestored && !$0.properties.isRestored })
            let workspace = try #require(try context.fetch(FetchDescriptor<Workspace>()).first)
            #expect(workspace.syncTree == nil && workspace.syncDeviceID == nil && workspace.syncCursors == nil)
            // Die neuen Felder lassen sich schreiben.
            blocks[0].properties.isRestored = true
            workspace.syncDeviceID = UUID()
            try context.save()
            #expect(try ModelContext(container).fetch(FetchDescriptor<Block>()).contains { $0.isRestored })
        }

        @Test func rehearsalV2ToV3() throws {
            defer { try? FileManager.default.removeItem(at: directory) }
            let fixture = try makeV1Store()
            let backup = StoreBackup(
                storeURL: storeURL,
                backupsURL: directory.appending(path: "Backups"),
                schemaVersion: "1.0.0"
            )
            try backup.markOpened()

            // Ablauf wie in der App: Backup vor dem Öffnen, dann migrieren.
            let upgraded = StoreBackup(
                storeURL: storeURL,
                backupsURL: backup.backupsURL,
                schemaVersion: "3.0.0"
            )
            let backupFolder = try #require(try upgraded.backupBeforeOpening())
            #expect(backupFolder.lastPathComponent.hasSuffix("_vor-migration-1.0.0-3.0.0"))

            let schema = Schema(versionedSchema: RehearsalSchemaV3.self)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: RehearsalMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            )
            try upgraded.markOpened()

            let pages = try ModelContext(container).fetch(FetchDescriptor<RehearsalSchemaV3.Page>())
            #expect(pages.count == 3)
            let child = try #require(pages.first { $0.id == fixture.childID })
            #expect(child.parent?.id == fixture.rootID)
            #expect(child.blocks?.count == 3)
            // Von der Migrationsstufe aus vorhandenen Daten berechnet.
            #expect(child.blockCount == 3)
            #expect(pages.first { $0.id == fixture.rootID }?.blockCount == 0)
            // Neues Feld mit Default.
            #expect(pages.allSatisfy { !$0.isLocked })

            // Das Backup ist weiterhin ein lesbarer V1-Store.
            let v1Schema = Schema(versionedSchema: SchemaV1.self)
            let v1 = try ModelContainer(
                for: v1Schema,
                configurations: ModelConfiguration(
                    schema: v1Schema,
                    url: backupFolder.appending(path: "Quill.store"),
                    allowsSave: false,
                    cloudKitDatabase: .none
                )
            )
            #expect(try ModelContext(v1).fetchCount(FetchDescriptor<SchemaV1.Page>()) == 3)
        }
    }
}

// MARK: - Probe-Schema V3 (nur im Test)

/// Echte Kette plus eine Probeversion. Beweist, dass Migrationen samt eigener
/// Stufe funktionieren, bevor wir sie wirklich brauchen.
enum RehearsalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        QuillMigrationPlan.schemas + [RehearsalSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        QuillMigrationPlan.stages + [
            .custom(
                fromVersion: SchemaV2.self,
                toVersion: RehearsalSchemaV3.self,
                willMigrate: nil,
                didMigrate: { context in
                    for page in try context.fetch(FetchDescriptor<RehearsalSchemaV3.Page>()) {
                        page.blockCount = page.blocks?.count ?? 0
                    }
                    try context.save()
                }
            ),
        ]
    }
}

/// `SchemaV2` plus zwei Felder an `Page`: `isLocked` (Default) und
/// `blockCount` (von der Stufe berechnet).
enum RehearsalSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Workspace.self, Page.self, Block.self, Asset.self]
    }

    @Model
    final class Workspace {
        var id: UUID = UUID()
        var name: String = "Mein Workspace"
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        @Attribute(.externalStorage)
        var syncTree: Data?
        var syncDeviceID: UUID?
        var syncCursors: Data?
        @Relationship(deleteRule: .cascade, inverse: \Page.workspace)
        var pages: [Page]? = []
        init() {}
    }

    @Model
    final class Page {
        var id: UUID = UUID()
        var title: String = ""
        var icon: String?
        var sortKey: String = ""
        var isFavorite: Bool = false
        var favoriteSortKey: String?
        var trashedAt: Date?
        var kindRaw: String = "page"
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        @Attribute(.externalStorage)
        var syncDocument: Data?
        var isRestored: Bool = false
        var isLocked: Bool = false
        var blockCount: Int = 0
        var workspace: Workspace?
        var parent: Page?
        @Relationship(deleteRule: .cascade, inverse: \Page.parent)
        var children: [Page]? = []
        @Relationship(deleteRule: .cascade, inverse: \Block.page)
        var blocks: [Block]? = []
        init() {}
    }

    @Model
    final class Block {
        var id: UUID = UUID()
        var kindRaw: String = "paragraph"
        var sortKey: String = ""
        var indent: Int = 0
        var text: String = ""
        var richText: Data?
        var isChecked: Bool = false
        var codeLanguage: String?
        var isRestored: Bool = false
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        var page: Page?
        @Relationship(deleteRule: .cascade, inverse: \Asset.block)
        var asset: Asset?
        init() {}
    }

    @Model
    final class Asset {
        var id: UUID = UUID()
        @Attribute(.externalStorage)
        var data: Data?
        var uti: String = "public.png"
        var pixelWidth: Int = 0
        var pixelHeight: Int = 0
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        var block: Block?
        init() {}
    }
}
