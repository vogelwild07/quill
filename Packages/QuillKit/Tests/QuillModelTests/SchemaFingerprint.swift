import SwiftData

/// Lesbarer, stabiler Fingerabdruck eines Schemas: Entitäten, Attribute
/// (Typ, optional, Optionen) und Beziehungen (Ziel, Kardinalität, Löschregel,
/// Inverse), alphabetisch sortiert.
///
/// Als Text statt Hash, damit ein fehlschlagender Test zeigt, was sich geändert hat.
enum SchemaFingerprint {
    static func of(_ versionedSchema: any VersionedSchema.Type) -> String {
        let schema = Schema(versionedSchema: versionedSchema)
        return schema.entities
            .sorted { $0.name < $1.name }
            .map(describe)
            .joined(separator: "\n")
    }

    private static func describe(_ entity: Schema.Entity) -> String {
        let attributes = entity.attributes
            .sorted { $0.name < $1.name }
            .map { attribute in
                let type = "\(attribute.valueType)"
                var line = "  \(attribute.name): \(type)"
                if attribute.isOptional, !type.hasPrefix("Optional<") { line += "?" }
                if !attribute.options.isEmpty {
                    line += " [" + attribute.options.map { "\($0)" }.sorted().joined(separator: ", ") + "]"
                }
                return line
            }
        let relationships = entity.relationships
            .sorted { $0.name < $1.name }
            .map { relationship in
                let cardinality = relationship.isToOneRelationship ? "→" : "→>"
                let optional = relationship.isOptional ? "?" : ""
                let inverse = relationship.inverseName.map { " ⇄ \($0)" } ?? ""
                return "  \(relationship.name) \(cardinality) \(relationship.destination)\(optional) "
                    + "(\(relationship.deleteRule))\(inverse)"
            }
        let unique = entity.uniquenessConstraints.isEmpty ? "" : "  unique: \(entity.uniquenessConstraints)\n"
        return "\(entity.name)\n" + unique + (attributes + relationships).joined(separator: "\n")
    }
}
