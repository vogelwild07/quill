import SwiftData
import Testing
@testable import QuillModel

/// Wacht über eingefrorene Schemas (ADR-011).
///
/// Schlägt `schemaV1IsFrozen` fehl, wurde `SchemaV1` direkt geändert. Richtig ist:
/// Änderung zurücknehmen, `SchemaV2` mit Migrationsstufe anlegen, `CurrentSchema`
/// umstellen und einen Test „V1 → V2“ in `MigrationTests` ergänzen.
@Suite struct SchemaFingerprintTests {
    @Test func schemaV1IsFrozen() {
        #expect(SchemaFingerprint.of(SchemaV1.self) == Self.schemaV1)
    }

    /// Seit Phase 11.2 (ADR-029); Änderungen nur über `SchemaV3` plus Stufe.
    @Test func schemaV2IsFrozen() {
        #expect(SchemaFingerprint.of(SchemaV2.self) == Self.schemaV2)
    }

    /// Regeln aus `docs/data-model.md` für jede Version im Migrationsplan.
    @Test(arguments: QuillMigrationPlan.schemas.map { SchemaBox($0) })
    func schemaFollowsCloudKitRules(_ box: SchemaBox) {
        for entity in Schema(versionedSchema: box.schema).entities {
            let names = Set(entity.attributes.map(\.name))
            #expect(names.isSuperset(of: ["id", "createdAt", "updatedAt"]), "\(entity.name)")
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name): kein .unique")
            for attribute in entity.attributes {
                #expect(!attribute.options.contains(.unique), "\(entity.name).\(attribute.name)")
            }
            for relationship in entity.relationships {
                #expect(relationship.isOptional, "\(entity.name).\(relationship.name) muss optional sein")
                #expect(relationship.inverseName != nil, "\(entity.name).\(relationship.name) braucht eine Inverse")
            }
        }
    }

    @Test func currentSchemaIsLastInPlan() {
        #expect(QuillMigrationPlan.schemas.last == CurrentSchema.self)
    }

    static let schemaV1 = """
        Asset
          createdAt: Date
          data: Optional<Data> [externalStorage]
          id: UUID
          pixelHeight: Int
          pixelWidth: Int
          updatedAt: Date
          uti: String
          block → Block? (nullify) ⇄ asset
        Block
          codeLanguage: Optional<String>
          createdAt: Date
          id: UUID
          indent: Int
          isChecked: Bool
          kindRaw: String
          richText: Optional<Data>
          sortKey: String
          text: String
          updatedAt: Date
          asset → Asset? (cascade) ⇄ block
          page → Page? (nullify) ⇄ blocks
        Page
          createdAt: Date
          favoriteSortKey: Optional<String>
          icon: Optional<String>
          id: UUID
          isFavorite: Bool
          kindRaw: String
          sortKey: String
          title: String
          trashedAt: Optional<Date>
          updatedAt: Date
          blocks →> Block? (cascade) ⇄ page
          children →> Page? (cascade) ⇄ parent
          parent → Page? (nullify) ⇄ children
          workspace → Workspace? (nullify) ⇄ pages
        Workspace
          createdAt: Date
          id: UUID
          name: String
          updatedAt: Date
          pages →> Page? (cascade) ⇄ workspace
        """

    static let schemaV2 = """
        Asset
          createdAt: Date
          data: Optional<Data> [externalStorage]
          id: UUID
          pixelHeight: Int
          pixelWidth: Int
          updatedAt: Date
          uti: String
          block → Block? (nullify) ⇄ asset
        Block
          codeLanguage: Optional<String>
          createdAt: Date
          id: UUID
          indent: Int
          isChecked: Bool
          isRestored: Bool
          kindRaw: String
          richText: Optional<Data>
          sortKey: String
          text: String
          updatedAt: Date
          asset → Asset? (cascade) ⇄ block
          page → Page? (nullify) ⇄ blocks
        Page
          createdAt: Date
          favoriteSortKey: Optional<String>
          icon: Optional<String>
          id: UUID
          isFavorite: Bool
          isRestored: Bool
          kindRaw: String
          sortKey: String
          syncDocument: Optional<Data> [externalStorage]
          title: String
          trashedAt: Optional<Date>
          updatedAt: Date
          blocks →> Block? (cascade) ⇄ page
          children →> Page? (cascade) ⇄ parent
          parent → Page? (nullify) ⇄ children
          workspace → Workspace? (nullify) ⇄ pages
        Workspace
          createdAt: Date
          id: UUID
          name: String
          syncCursors: Optional<Data>
          syncDeviceID: Optional<UUID>
          syncTree: Optional<Data> [externalStorage]
          updatedAt: Date
          pages →> Page? (cascade) ⇄ workspace
        """
}

/// `VersionedSchema.Type` als Testargument (Swift Testing braucht `Sendable` + Beschreibung).
struct SchemaBox: Sendable, CustomTestStringConvertible {
    let schema: any VersionedSchema.Type
    init(_ schema: any VersionedSchema.Type) { self.schema = schema }
    var testDescription: String { "\(schema)" }
}
