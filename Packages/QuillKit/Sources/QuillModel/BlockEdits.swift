import Foundation
import SwiftData

/// Inhalt eines Blocks als `Sendable`-Werttyp für die Schnittstelle von `PageStore`.
public struct BlockSnapshot: Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Rohwert von `BlockKind`; unbekannte Werte späterer Versionen bleiben erhalten.
    public var kindRaw: String
    public var text: String
    public var richText: Data?
    public var indent: Int
    public var isChecked: Bool
    public var codeLanguage: String?

    public init(
        id: UUID,
        kindRaw: String = BlockKind.paragraph.rawValue,
        text: String = "",
        richText: Data? = nil,
        indent: Int = 0,
        isChecked: Bool = false,
        codeLanguage: String? = nil
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.text = text
        self.richText = richText
        self.indent = indent
        self.isChecked = isChecked
        self.codeLanguage = codeLanguage
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
    var snapshot: BlockSnapshot {
        BlockSnapshot(
            id: id, kindRaw: kindRaw, text: text, richText: richText,
            indent: indent, isChecked: isChecked, codeLanguage: codeLanguage
        )
    }

    /// Übernimmt den Inhalt; `true`, wenn sich etwas geändert hat.
    func apply(_ snapshot: BlockSnapshot) -> Bool {
        guard self.snapshot != snapshot else { return false }
        kindRaw = snapshot.kindRaw
        text = snapshot.text
        richText = snapshot.richText
        indent = snapshot.indent
        isChecked = snapshot.isChecked
        codeLanguage = snapshot.codeLanguage
        return true
    }
}
