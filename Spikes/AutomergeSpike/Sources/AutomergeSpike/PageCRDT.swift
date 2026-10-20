import Automerge
import Foundation
import QuillEditor
import QuillModel

public enum SpikeError: Error {
    case malformed(String)
}

/// Eine Seite als Automerge-Dokument nach ADR-026: `blocks` ist eine Liste von Maps
/// mit `id`, `kind` (Rohwert von `BlockKind`), `text` (Text mit Marks) und den
/// Feldern aus `BlockProperties` (`indent`, `checked`, `lang`, `asset`).
///
/// Automerge zählt Textpositionen in Unicode-Skalaren; ein geladenes Dokument kennt
/// keine andere Kodierung. Der Editor zählt in UTF-16, deshalb rechnet diese Klasse
/// beim Lesen um.
public final class PageCRDT {
    public let document: Document
    public let blocksID: ObjId

    public init(blocks: [EditorBlock] = []) throws {
        document = Document()
        blocksID = try document.putObject(obj: .ROOT, key: "blocks", ty: .List)
        for (index, block) in blocks.enumerated() {
            try insertBlock(block, at: index)
        }
        document.commitWith()
    }

    public convenience init(bytes: Data) throws {
        try self.init(document: Document(bytes))
    }

    public init(document: Document) throws {
        self.document = document
        guard case .Object(let id, .List)? = try document.get(obj: .ROOT, key: "blocks") else {
            throw SpikeError.malformed("blocks fehlt")
        }
        blocksID = id
    }

    /// Eigene Kopie mit neuer Akteurs-ID, wie ein zweites Gerät.
    public func fork() throws -> PageCRDT {
        try PageCRDT(document: document.fork())
    }

    public func merge(_ other: PageCRDT) throws {
        try document.merge(other: other.document)
    }

    // MARK: Schreiben

    /// Fügt einen Block ein und gibt die ID seines Textobjekts zurück.
    @discardableResult
    public func insertBlock(_ block: EditorBlock, at index: Int) throws -> ObjId {
        let map = try document.insertObject(obj: blocksID, index: UInt64(index), ty: .Map)
        try document.put(obj: map, key: "id", value: .String(block.id.uuidString))
        try document.put(obj: map, key: "kind", value: .String(block.kind.rawValue))
        try document.put(obj: map, key: "indent", value: .Int(Int64(block.indent)))
        try document.put(obj: map, key: "checked", value: .Boolean(block.isChecked))
        if let language = block.codeLanguage {
            try document.put(obj: map, key: "lang", value: .String(language))
        }
        if let asset = block.assetID {
            try document.put(obj: map, key: "asset", value: .String(asset.uuidString))
        }
        let text = try document.putObject(obj: map, key: "text", ty: .Text)
        try document.spliceText(obj: text, start: 0, delete: 0, value: block.text)
        let scalars = Self.scalarOffsets(block.text)
        for span in block.spans {
            let start = scalars[span.range.lowerBound], end = scalars[span.range.upperBound]
            try mark(text, start: start, end: end, style: span.style)
        }
        return text
    }

    /// Setzt Marks in Skalar-Positionen. Fett, kursiv usw. wachsen beim Weitertippen
    /// am Ende mit, Links nicht (wie im Editor).
    public func mark(_ text: ObjId, start: Int, end: Int, style: InlineStyle) throws {
        for mark in style.marks {
            try document.mark(
                obj: text, start: UInt64(start), end: UInt64(end), expand: .after,
                name: mark.rawValue, value: .Boolean(true)
            )
        }
        if let link = style.link {
            try document.mark(
                obj: text, start: UInt64(start), end: UInt64(end), expand: .none,
                name: "link", value: .String(link)
            )
        }
    }

    public func map(at index: Int) throws -> ObjId {
        guard case .Object(let map, .Map)? = try document.get(obj: blocksID, index: UInt64(index)) else {
            throw SpikeError.malformed("Block \(index) ist keine Map")
        }
        return map
    }

    public func textObject(at index: Int) throws -> ObjId {
        guard case .Object(let text, .Text)? = try document.get(obj: map(at: index), key: "text") else {
            throw SpikeError.malformed("Block \(index) ohne Text")
        }
        return text
    }

    // MARK: Lesen

    public var blockCount: Int { Int(document.length(obj: blocksID)) }

    /// Alle Blöcke als `EditorBlock`, wie der Editor sie braucht.
    public func blocks() throws -> [EditorBlock] {
        try (0..<blockCount).map { try block(map: map(at: $0)) }
    }

    func block(map: ObjId) throws -> EditorBlock {
        var fields: [String: Value] = [:]
        for (key, value) in try document.mapEntries(obj: map) {
            fields[key] = value
        }
        guard case .Scalar(.String(let idString))? = fields["id"], let id = UUID(uuidString: idString) else {
            throw SpikeError.malformed("Block ohne ID")
        }
        guard case .Scalar(.String(let kindRaw))? = fields["kind"] else {
            throw SpikeError.malformed("Block ohne Art")
        }
        guard case .Object(let textID, .Text)? = fields["text"] else {
            throw SpikeError.malformed("Block ohne Text")
        }
        var properties = BlockProperties()
        if case .Scalar(.Int(let indent))? = fields["indent"] { properties.indent = Int(indent) }
        if case .Scalar(.Boolean(let checked))? = fields["checked"] { properties.isChecked = checked }
        if case .Scalar(.String(let language))? = fields["lang"] { properties.codeLanguage = language }
        if case .Scalar(.String(let asset))? = fields["asset"] { properties.assetID = UUID(uuidString: asset) }
        let text = try document.text(obj: textID)
        let marks = try document.marks(obj: textID)
        // Unbekannte Arten späterer Versionen: im Spike als Absatz.
        return EditorBlock(
            id: id, kind: BlockKind(rawValue: kindRaw) ?? .paragraph, text: text,
            spans: marks.isEmpty ? [] : Self.spans(from: marks, in: text), properties: properties
        )
    }

    /// Automerge liefert Marks einzeln und überlappend; der Editor braucht
    /// überlappungsfreie Spans in UTF-16 (`InlineText.normalized` fasst zusammen).
    static func spans(from marks: [Mark], in text: String) -> [InlineSpan] {
        let utf16 = utf16Offsets(text)
        var bounds = Set<Int>()
        for mark in marks {
            bounds.insert(Int(mark.start))
            bounds.insert(Int(mark.end))
        }
        let sorted = bounds.sorted()
        var spans: [InlineSpan] = []
        for (start, end) in zip(sorted, sorted.dropFirst()) where start < end {
            var style = InlineStyle()
            for mark in marks where Int(mark.start) <= start && Int(mark.end) >= end {
                switch mark.value {
                case .Boolean(true): style.marks.insert(InlineMark(rawValue: mark.name))
                case .String(let link) where mark.name == "link": style.link = link
                default: break
                }
            }
            if !style.isPlain {
                spans.append(InlineSpan(utf16[start]..<utf16[end], style))
            }
        }
        return spans
    }

    /// UTF-16-Offset → Skalar-Offset, Index ist der UTF-16-Offset (inklusive Ende).
    static func scalarOffsets(_ text: String) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(text.utf16.count + 1)
        var scalarIndex = 0
        for scalar in text.unicodeScalars {
            for _ in 0..<scalar.utf16.count { result.append(scalarIndex) }
            scalarIndex += 1
        }
        result.append(scalarIndex)
        return result
    }

    /// Skalar-Offset → UTF-16-Offset, Index ist der Skalar-Offset (inklusive Ende).
    static func utf16Offsets(_ text: String) -> [Int] {
        var result: [Int] = [0]
        result.reserveCapacity(text.unicodeScalars.count + 1)
        var offset = 0
        for scalar in text.unicodeScalars {
            offset += scalar.utf16.count
            result.append(offset)
        }
        return result
    }
}
