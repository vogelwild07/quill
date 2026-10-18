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

    /// Code und atomare Blöcke tragen keine Inline-Formatierung.
    public var allowsInlineMarks: Bool {
        self != .code && !isAtomic
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
    /// Inline-Formatierung über `text` (UTF-16). Leer in Code-Blöcken und atomaren Blöcken.
    public var spans: [InlineSpan]
    public var indent: Int
    public var isChecked: Bool
    public var codeLanguage: String?

    public init(
        id: UUID = UUID(),
        kind: BlockKind = .paragraph,
        text: String = "",
        spans: [InlineSpan] = [],
        indent: Int = 0,
        isChecked: Bool = false,
        codeLanguage: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.spans = kind.allowsInlineMarks ? InlineText.normalized(spans, length: text.utf16.count) : []
        self.indent = indent
        self.isChecked = isChecked
        self.codeLanguage = codeLanguage
    }

    /// Länge in UTF-16-Einheiten, wie `NSString` und `NSTextView` zählen.
    public var length: Int { text.utf16.count }

    /// Text und Formatierung zusammen. Setzen hält die Regel ein, dass Code-Blöcke
    /// keine Marks haben.
    public var content: InlineText {
        get { InlineText(text, spans: spans) }
        set {
            text = newValue.text
            spans = kind.allowsInlineMarks ? newValue.spans : []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, spans, indent, isChecked, codeLanguage
    }

    /// `spans` fehlt in Zwischenablage-Daten älterer Versionen.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            kind: try container.decode(BlockKind.self, forKey: .kind),
            text: try container.decode(String.self, forKey: .text),
            spans: try container.decodeIfPresent([InlineSpan].self, forKey: .spans) ?? [],
            indent: try container.decode(Int.self, forKey: .indent),
            isChecked: try container.decode(Bool.self, forKey: .isChecked),
            codeLanguage: try container.decodeIfPresent(String.self, forKey: .codeLanguage)
        )
    }
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
