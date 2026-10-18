import SwiftData

/// Aktuelles Schema der App. Bei einer neuen Version hier umstellen.
public typealias CurrentSchema = SchemaV1

public typealias Workspace = CurrentSchema.Workspace
public typealias Page = CurrentSchema.Page
public typealias Block = CurrentSchema.Block
public typealias Asset = CurrentSchema.Asset

/// Migrationskette aller Schema-Versionen, älteste zuerst.
///
/// Jede neue Version bekommt eine Stufe und einen Test „V(n-1) → V(n)“ in
/// `MigrationTests` (ADR-010).
public enum QuillMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
