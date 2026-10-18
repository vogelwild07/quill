import Foundation

/// Art eines Blocks. Rohwerte entsprechen `Block.kindRaw` im Datenmodell.
public enum BlockKind: String, Codable, Sendable, CaseIterable {
    case paragraph
    case heading1, heading2, heading3
    case bulleted, numbered, todo
    case quote, code, divider, image

    /// Listenartige Blöcke setzen sich bei Enter fort.
    public var isListItem: Bool {
        self == .bulleted || self == .numbered || self == .todo
    }

    public var isHeading: Bool {
        self == .heading1 || self == .heading2 || self == .heading3
    }

    /// Blöcke ohne editierbaren Text (stehen im Textsystem als Attachment).
    public var isAtomic: Bool {
        self == .divider || self == .image
    }

    /// Blöcke, die mit Tab eingerückt werden können.
    public var isIndentable: Bool {
        isListItem || self == .paragraph
    }
}

/// Ein Block im Editor. Werttyp; die einzige Wahrheit über Inhalt und Art.
public struct EditorBlock: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var kind: BlockKind
    /// Klartext. Weiche Zeilenumbrüche (Code, ⇧↩) sind `\n`.
    public var text: String
    public var indent: Int
    public var isChecked: Bool
    public var codeLanguage: String?

    public init(
        id: UUID = UUID(),
        kind: BlockKind = .paragraph,
        text: String = "",
        indent: Int = 0,
        isChecked: Bool = false,
        codeLanguage: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.indent = indent
        self.isChecked = isChecked
        self.codeLanguage = codeLanguage
    }

    /// Länge in UTF-16-Einheiten, wie `NSString` und `NSTextView` zählen.
    public var length: Int { text.utf16.count }
}

/// Cursorposition: Block-Index und Offset in UTF-16-Einheiten.
public struct BlockPosition: Equatable, Sendable, CustomStringConvertible {
    public var block: Int
    public var offset: Int

    public init(block: Int, offset: Int) {
        self.block = block
        self.offset = offset
    }

    public var description: String { "(\(block), \(offset))" }
}
