import Foundation
import SwiftData

/// Inhalt eines Blocks als `Sendable`-Werttyp für die Schnittstelle von `PageStore`.
public struct BlockSnapshot: Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Rohwert von `BlockKind`; unbekannte Werte späterer Versionen bleiben erhalten.
    public var kindRaw: String
    public var text: String
    public var richText: Data?
    public var properties: BlockProperties

    public init(
        id: UUID,
        kindRaw: String = BlockKind.paragraph.rawValue,
        text: String = "",
        richText: Data? = nil,
        properties: BlockProperties = BlockProperties()
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.text = text
        self.richText = richText
        self.properties = properties
    }
}

/// Änderungen an den Blöcken einer Seite, wie sie die `EditorPersistenceBridge` sammelt.
public struct BlockEdits: Equatable, Sendable {
    /// Neue oder geänderte Blöcke.
    public var upserts: [BlockSnapshot]
    public var deletions: [UUID]
    /// Gewünschte Reihenfolge oder `nil` = unverändert. Blöcke, die hier fehlen
    /// (z. B. aus einem anderen Fenster), behalten ihren Schlüssel.
    public var order: [UUID]?

    public init(upserts: [BlockSnapshot] = [], deletions: [UUID] = [], order: [UUID]? = nil) {
        self.upserts = upserts
        self.deletions = deletions
        self.order = order
    }

    public var isEmpty: Bool { upserts.isEmpty && deletions.isEmpty && order == nil }
}

extension Block {
    /// Die einzige Abbildung von `BlockProperties` auf Spalten und Beziehungen des Modells.
    public var properties: BlockProperties {
        get { BlockProperties(indent: indent, isChecked: isChecked, codeLanguage: codeLanguage, assetID: asset?.id) }
        set {
            indent = newValue.indent
            isChecked = newValue.isChecked
            codeLanguage = newValue.codeLanguage
            if asset?.id != newValue.assetID {
                linkAsset(newValue.assetID)
            }
        }
    }

    /// Verknüpft das Asset mit dieser ID. Gehört es schon einem anderen Block
    /// (z. B. eingesetzt auf einer zweiten Seite), bekommt dieser Block eine Kopie,
    /// statt es dem anderen wegzunehmen. Ein gelöstes Asset bleibt als verwaist
    /// liegen, bis `PageStore.removeOrphanedAssets` es aufräumt (ADR-015).
    private func linkAsset(_ id: UUID?) {
        if let old = asset { old.updatedAt = .now }
        guard let id, let context = modelContext else {
            asset = nil
            return
        }
        let found = try? context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })).first
        guard let found else {
            asset = nil
            return
        }
        if let owner = found.block, owner !== self {
            let copy = Asset(data: found.data, uti: found.uti)
            copy.pixelWidth = found.pixelWidth
            copy.pixelHeight = found.pixelHeight
            context.insert(copy)
            asset = copy
        } else {
            asset = found
        }
        asset?.updatedAt = .now
    }

    var snapshot: BlockSnapshot {
        BlockSnapshot(id: id, kindRaw: kindRaw, text: text, richText: richText, properties: properties)
    }

    /// Übernimmt den Inhalt; `true`, wenn sich etwas geändert hat.
    func apply(_ snapshot: BlockSnapshot) -> Bool {
        guard self.snapshot != snapshot else { return false }
        kindRaw = snapshot.kindRaw
        text = snapshot.text
        richText = snapshot.richText
        properties = snapshot.properties
        return true
    }
}
