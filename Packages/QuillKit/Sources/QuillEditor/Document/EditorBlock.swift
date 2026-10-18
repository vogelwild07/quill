import Foundation
import QuillModel

/// Verhalten der Blockarten im Editor; die Arten selbst stehen in `QuillModel`.
extension BlockKind {
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
///
/// Die einfachen Felder liegen gebündelt in `properties` und sind über
/// `@dynamicMemberLookup` direkt erreichbar (`block.indent`).
@dynamicMemberLookup
public struct EditorBlock: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var kind: BlockKind
    /// Klartext. Weiche Zeilenumbrüche (Code, ⇧↩) sind `\n`.
    public var text: String
    /// Inline-Formatierung über `text` (UTF-16). Leer in Code-Blöcken und atomaren Blöcken.
    public var spans: [InlineSpan]
    public var properties: BlockProperties

    public init(
        id: UUID = UUID(),
        kind: BlockKind = .paragraph,
        text: String = "",
        spans: [InlineSpan] = [],
        properties: BlockProperties
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.spans = kind.allowsInlineMarks ? InlineText.normalized(spans, length: text.utf16.count) : []
        self.properties = properties
    }

    public init(
        id: UUID = UUID(),
        kind: BlockKind = .paragraph,
        text: String = "",
        spans: [InlineSpan] = [],
        indent: Int = 0,
        isChecked: Bool = false,
        codeLanguage: String? = nil
    ) {
        self.init(
            id: id, kind: kind, text: text, spans: spans,
            properties: BlockProperties(indent: indent, isChecked: isChecked, codeLanguage: codeLanguage)
        )
    }

    public subscript<Value>(dynamicMember keyPath: WritableKeyPath<BlockProperties, Value>) -> Value {
        get { properties[keyPath: keyPath] }
        set { properties[keyPath: keyPath] = newValue }
    }

    /// Kopie mit neuer ID (Einsetzen, Duplizieren); Inhalt und Felder bleiben.
    public func withNewID() -> EditorBlock {
        var copy = self
        copy.id = UUID()
        return copy
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
        case id, kind, text, spans, properties
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            kind: try container.decode(BlockKind.self, forKey: .kind),
            text: try container.decode(String.self, forKey: .text),
            spans: try container.decode([InlineSpan].self, forKey: .spans),
            properties: try container.decode(BlockProperties.self, forKey: .properties)
        )
    }
}

extension BlockProperties {
    /// Hält die Regeln ein, welche Felder zu welcher Blockart passen: Häkchen nur
    /// bei To-dos, Sprache nur bei Code, Bild nur bei Bild-Blöcken, keine Einrückung bei Überschriften, Code,
    /// Zitaten und atomaren Blöcken.
    func normalized(for kind: BlockKind) -> BlockProperties {
        var result = self
        if kind != .todo { result.isChecked = false }
        if kind != .code { result.codeLanguage = nil }
        if kind != .image { result.assetID = nil }
        if kind.isAtomic || kind.isHeading || kind == .code || kind == .quote {
            result.indent = 0
        }
        result.indent = max(0, min(result.indent, EditorDocument.maxIndent))
        return result
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
