import Foundation
import SwiftData

/// Zweite Version des Quill-Schemas (Phase 11.2, ADR-029): `SchemaV1` plus Felder für
/// den Ordner-Sync. Alle neuen Felder sind leer oder `false`; die Stufe von V1 ist
/// leichtgewichtig, Inhalte bleiben unverändert. Regeln siehe `docs/data-model.md`.
///
/// Nach dem Release nie mehr ändern: Neue Felder kommen in `SchemaV3` plus
/// Migrationsstufe. `SchemaFingerprintTests` schlägt sonst fehl.
public enum SchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [Workspace.self, Page.self, Block.self, Asset.self]
    }
}

extension SchemaV2 {
    @Model
    public final class Workspace {
        public var id: UUID = UUID()
        public var name: String = "Mein Workspace"
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now
        /// Seitenbaum als Sync-Dokument (`QuillSync.TreeDocument`); `nil` ohne Sync.
        @Attribute(.externalStorage)
        public var syncTree: Data?
        /// Geräte-ID im Sync-Ordner; `nil`, bis der Sync zum ersten Mal eingeschaltet wird.
        public var syncDeviceID: UUID?
        /// Welche Dateien im Sync-Ordner schon gelesen sind, je Gerät (JSON aus QuillSync).
        public var syncCursors: Data?

        @Relationship(deleteRule: .cascade, inverse: \Page.workspace)
        public var pages: [Page]? = []

        public init(name: String = "Mein Workspace") {
            self.name = name
        }
    }

    @Model
    public final class Page {
        public var id: UUID = UUID()
        public var title: String = ""
        /// Emoji oder `nil`.
        public var icon: String?
        /// Reihenfolge unter Geschwistern, siehe `FractionalIndex`.
        public var sortKey: String = ""
        public var isFavorite: Bool = false
        public var favoriteSortKey: String?
        /// `nil` = aktiv. Unterseiten liegen logisch mit im Papierkorb.
        public var trashedAt: Date?
        /// Rohwert von `PageKind`.
        public var kindRaw: String = PageKind.page.rawValue
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now
        /// Blöcke als Sync-Dokument (`QuillSync.PageDocument`); `nil` ohne Sync.
        @Attribute(.externalStorage)
        public var syncDocument: Data?
        /// Vom Sync wiederhergestellt (gelöscht auf einem Gerät, bearbeitet auf einem anderen).
        public var isRestored: Bool = false

        public var workspace: Workspace?
        public var parent: Page?

        @Relationship(deleteRule: .cascade, inverse: \Page.parent)
        public var children: [Page]? = []

        @Relationship(deleteRule: .cascade, inverse: \Block.page)
        public var blocks: [Block]? = []

        public init(title: String = "", sortKey: String = "") {
            self.title = title
            self.sortKey = sortKey
        }

        /// Unbekannte Rohwerte späterer Versionen werden als `.page` gelesen.
        public var kind: PageKind {
            get { PageKind(rawValue: kindRaw) ?? .page }
            set { kindRaw = newValue.rawValue }
        }
    }

    @Model
    public final class Block {
        public var id: UUID = UUID()
        /// Rohwert von `BlockKind`.
        public var kindRaw: String = BlockKind.paragraph.rawValue
        public var sortKey: String = ""
        public var indent: Int = 0
        /// Klartext für Suche und Export.
        public var text: String = ""
        /// Codable-JSON mit Runs und Marks; `nil` = nur Klartext.
        public var richText: Data?
        public var isChecked: Bool = false
        public var codeLanguage: String?
        /// Vom Sync wiederhergestellt; Teil von `BlockProperties`.
        public var isRestored: Bool = false
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public var page: Page?

        @Relationship(deleteRule: .cascade, inverse: \Asset.block)
        public var asset: Asset?

        public init(kind: BlockKind = .paragraph, text: String = "", sortKey: String = "") {
            self.kindRaw = kind.rawValue
            self.text = text
            self.sortKey = sortKey
        }

        /// Unbekannte Rohwerte späterer Versionen werden als `.paragraph` gelesen.
        public var kind: BlockKind {
            get { BlockKind(rawValue: kindRaw) ?? .paragraph }
            set { kindRaw = newValue.rawValue }
        }
    }

    @Model
    public final class Asset {
        public var id: UUID = UUID()
        @Attribute(.externalStorage)
        public var data: Data?
        public var uti: String = "public.png"
        public var pixelWidth: Int = 0
        public var pixelHeight: Int = 0
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public var block: Block?

        public init(data: Data? = nil, uti: String = "public.png") {
            self.data = data
            self.uti = uti
        }
    }
}
