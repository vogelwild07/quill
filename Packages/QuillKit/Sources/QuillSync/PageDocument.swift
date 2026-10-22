import Automerge
import Foundation
import QuillModel

/// Blöcke einer Seite als Automerge-Dokument (ADR-026, ADR-029).
///
/// `blocks` ist eine Map von Block-ID auf eine Map mit `kind` (Rohwert von `BlockKind`,
/// unbekannte bleiben erhalten), `order` (Schlüssel aus `FractionalIndex`), `text`
/// (Text mit Marks), den Feldern aus `BlockProperties` (`indent`, `checked`, `lang`,
/// `asset`, `restored`) und `assetFile` (Name des Bildes im Ordner). Eine Map statt
/// einer Liste, damit Verschieben nur `order` ändert und gleichzeitiges Tippen im
/// verschobenen Block erhalten bleibt.
public final class PageDocument: SyncDocument {
    override class var itemsKey: String { "blocks" }
    /// Felder, deren gleichzeitige Änderung der Nutzer entscheidet. `order` nicht:
    /// Zwei Reihenfolgen verlieren keinen Inhalt, Automerge wählt fest eine.
    static let conflictFields = ["kind", "indent", "checked", "lang", "asset"]

    /// Blöcke in Dokument-Reihenfolge; mit `version` der Stand von damals.
    public func blocks(at version: DocumentVersion? = nil) throws -> [BlockSnapshot] {
        try entries(at: version?.heads).map(\.block)
    }

    /// Dateinamen der Bilder im Ordner (`assets/<SHA-256>.<Endung>`) je Asset-ID.
    public func assetFiles() throws -> [UUID: String] {
        var result: [UUID: String] = [:]
        for entry in try entries(at: nil) {
            if let asset = entry.block.properties.assetID, let file = entry.assetFile { result[asset] = file }
        }
        return result
    }

    /// Bringt das Dokument auf den Stand `blocks` (Reihenfolge wie im Array) und hält
    /// die Änderung als Commit fest. Text wird als Diff geschrieben, damit gleichzeitiges
    /// Tippen auf anderen Geräten erhalten bleibt. `assetFiles` nennt die Datei im Ordner
    /// je Asset-ID. `true`, wenn sich etwas geändert hat.
    @discardableResult
    public func update(to blocks: [BlockSnapshot], assetFiles: [UUID: String] = [:]) throws -> Bool {
        var changed = false
        let wanted = Set(blocks.map(\.id))
        var existing: [UUID: ObjId] = [:]
        for (id, key) in itemKeys() {
            if wanted.contains(id), let map = try map(key) {
                existing[id] = map
            } else {
                try document.delete(obj: itemsID, key: key)
                changed = true
            }
        }
        let orders = try orderKeys(for: blocks, existing: existing)
        for (block, order) in zip(blocks, orders) {
            let assetFile = block.properties.assetID.flatMap { assetFiles[$0] }
            if let map = existing[block.id] {
                changed = try update(map, to: block, order: order, assetFile: assetFile) || changed
            } else {
                try insert(block, order: order, assetFile: assetFile)
                changed = true
            }
        }
        if changed { commit() }
        return changed
    }

    /// Löschen gegen Bearbeiten (ADR-026): Hat ein anderes Gerät einen Block gelöscht,
    /// den dieses Gerät bearbeitet hatte, ohne dass das löschende Gerät die Bearbeitung
    /// kannte, kommt der Block mit dem Stand dieses Geräts zurück und ist als
    /// wiederhergestellt markiert. `version` ist der Stand vor `apply(changes:)`.
    /// Gibt die IDs der wiederhergestellten Blöcke zurück.
    @discardableResult
    public func restoreDeletedWhileEdited(since version: DocumentVersion) throws -> [UUID] {
        let current = Set(itemKeys().map(\.0))
        let vanished = try entries(at: version.heads).filter { !current.contains($0.block.id) }
        guard !vanished.isEmpty else { return [] }
        let incoming = try changes(after: version)
        var restored: [UUID] = []
        for mine in vanished {
            let key = mine.block.id.uuidString
            // Die Änderung, die den Block entfernt: vorher da, danach nicht mehr.
            let deletion = try incoming.first { change in
                try map(key, at: Set(change.deps)) != nil && map(key, at: [change.hash]) == nil
            }
            guard let deletion else { continue }
            let seen = try entries(at: Set(deletion.deps)).first { $0.block.id == mine.block.id }
            guard seen?.block != mine.block || seen?.assetFile != mine.assetFile else { continue }
            var block = mine.block
            block.properties.isRestored = true
            try insert(block, order: mine.order, assetFile: mine.assetFile)
            restored.append(block.id)
        }
        if !restored.isEmpty { commit() }
        return restored
    }

    // MARK: Lesen

    private struct Entry {
        var order: String
        var block: BlockSnapshot
        var assetFile: String?
    }

    private func entries(at heads: Set<ChangeHash>?) throws -> [Entry] {
        var result: [Entry] = []
        for (id, key) in itemKeys(at: heads) {
            guard let map = try map(key, at: heads) else { continue }
            result.append(try entry(id, map: map, at: heads))
        }
        return result.sorted { ($0.order, $0.block.id.uuidString) < ($1.order, $1.block.id.uuidString) }
    }

    private func entry(_ id: UUID, map: ObjId, at heads: Set<ChangeHash>?) throws -> Entry {
        let key = id.uuidString
        let fields = try fields(of: map, at: heads)
        guard case .Scalar(.String(let kindRaw))? = fields["kind"],
              case .Object(let textID, .Text)? = fields["text"]
        else {
            throw SyncError.malformed(key)
        }
        var properties = BlockProperties()
        if case .Scalar(.Int(let indent))? = fields["indent"] { properties.indent = Int(indent) }
        if case .Scalar(.Boolean(let checked))? = fields["checked"] { properties.isChecked = checked }
        if case .Scalar(.String(let language))? = fields["lang"] { properties.codeLanguage = language }
        if case .Scalar(.String(let asset))? = fields["asset"] { properties.assetID = UUID(uuidString: asset) }
        if case .Scalar(.Boolean(let restored))? = fields["restored"] { properties.isRestored = restored }
        let text = try heads.map { try document.textAt(obj: textID, heads: $0) } ?? document.text(obj: textID)
        let rawMarks = try heads.map { try document.marksAt(obj: textID, heads: $0) } ?? document.marks(obj: textID)
        let marks = TextMarks.assignments(of: rawMarks, count: text.unicodeScalars.count)
        var order = ""
        if case .Scalar(.String(let value))? = fields["order"] { order = value }
        var assetFile: String?
        if case .Scalar(.String(let value))? = fields["assetFile"] { assetFile = value }
        let block = BlockSnapshot(
            id: id, kindRaw: kindRaw, text: text,
            richText: TextMarks.richText(text: text, assignments: marks), properties: properties
        )
        return Entry(order: order, block: block, assetFile: assetFile)
    }

    override func summary(of map: ObjId) throws -> String? {
        guard case .Object(let textID, .Text)? = try fields(of: map)["text"] else { return nil }
        return try document.text(obj: textID)
    }

    override func rewrite(_ key: String, from map: ObjId) throws {
        guard let id = UUID(uuidString: key) else { return }
        let chosen = try entry(id, map: map, at: nil)
        try insert(chosen.block, order: chosen.order, assetFile: chosen.assetFile)
    }

    /// Gleichzeitige Änderungen derselben Felder, die der Nutzer entscheidet.
    public func conflicts() throws -> [FieldConflict] {
        try conflicts(in: Self.conflictFields)
    }

    // MARK: Schreiben

    private func insert(_ block: BlockSnapshot, order: String, assetFile: String?) throws {
        let map = try document.putObject(obj: itemsID, key: block.id.uuidString, ty: .Map)
        try document.put(obj: map, key: "kind", value: .String(block.kindRaw))
        try document.put(obj: map, key: "order", value: .String(order))
        try writeProperties(map, block.properties, fields: [:])
        if let assetFile { try document.put(obj: map, key: "assetFile", value: .String(assetFile)) }
        let text = try document.putObject(obj: map, key: "text", ty: .Text)
        try document.updateText(obj: text, value: block.text)
        try TextMarks.update(document, obj: text, to: TextMarks.assignments(text: block.text, richText: block.richText))
    }

    private func update(_ map: ObjId, to block: BlockSnapshot, order: String, assetFile: String?) throws -> Bool {
        let fields = try fields(of: map)
        var changed = try set(map, "kind", .String(block.kindRaw), current: fields["kind"])
        changed = try set(map, "order", .String(order), current: fields["order"]) || changed
        changed = try writeProperties(map, block.properties, fields: fields) || changed
        changed = try set(map, "assetFile", assetFile.map { .String($0) }, current: fields["assetFile"]) || changed
        let textID: ObjId
        if case .Object(let id, .Text)? = fields["text"] {
            textID = id
        } else {
            textID = try document.putObject(obj: map, key: "text", ty: .Text)
            changed = true
        }
        if try document.text(obj: textID) != block.text {
            try document.updateText(obj: textID, value: block.text)
            changed = true
        }
        let desired = TextMarks.assignments(text: block.text, richText: block.richText)
        if TextMarks.assignments(of: try document.marks(obj: textID), count: desired.count) != desired {
            try TextMarks.update(document, obj: textID, to: desired)
            changed = true
        }
        return changed
    }

    @discardableResult
    private func writeProperties(_ map: ObjId, _ properties: BlockProperties, fields: [String: Value]) throws -> Bool {
        var changed = try set(map, "indent", .Int(Int64(properties.indent)), current: fields["indent"])
        changed = try set(map, "checked", .Boolean(properties.isChecked), current: fields["checked"]) || changed
        changed = try set(map, "lang", properties.codeLanguage.map { .String($0) }, current: fields["lang"]) || changed
        changed = try set(map, "asset", properties.assetID.map { .String($0.uuidString) }, current: fields["asset"]) || changed
        // Nur gesetzt, solange die Marke steht; fehlt sonst, wie in älteren Dokumenten.
        changed = try set(map, "restored", properties.isRestored ? .Boolean(true) : nil, current: fields["restored"]) || changed
        return changed
    }

    /// Reihenfolge-Schlüssel für `blocks`: Blöcke, die schon in der richtigen relativen
    /// Reihenfolge stehen (längste aufsteigende Folge), behalten ihren Schlüssel; die
    /// anderen bekommen neue zwischen ihren Nachbarn. So ändert ein verschobener Block
    /// nur seinen eigenen Schlüssel.
    private func orderKeys(for blocks: [BlockSnapshot], existing: [UUID: ObjId]) throws -> [String] {
        var current: [String?] = []
        for block in blocks {
            if let map = existing[block.id], case .Scalar(.String(let key))? = try document.get(obj: map, key: "order"),
               FractionalIndex.isValid(key) {
                current.append(key)
            } else {
                current.append(nil)
            }
        }
        let kept = Self.longestIncreasingRun(current)
        var result = current.enumerated().map { kept.contains($0.offset) ? $0.element : nil }
        var index = 0
        while index < result.count {
            guard result[index] == nil else {
                index += 1
                continue
            }
            var end = index
            while end < result.count, result[end] == nil { end += 1 }
            let lower = index > 0 ? result[index - 1] : nil
            let upper = end < result.count ? result[end] : nil
            let keys = try FractionalIndex.keys(count: end - index, between: lower, and: upper)
            for (offset, key) in keys.enumerated() { result[index + offset] = key }
            index = end
        }
        return result.map { $0! }
    }

    /// Indizes der längsten streng aufsteigenden Teilfolge unter den vorhandenen Schlüsseln.
    static func longestIncreasingRun(_ keys: [String?]) -> Set<Int> {
        var tails: [Int] = []
        var previous = Array(repeating: -1, count: keys.count)
        for (index, key) in keys.enumerated() {
            guard let key else { continue }
            var low = 0, high = tails.count
            while low < high {
                let middle = (low + high) / 2
                if keys[tails[middle]]! < key { low = middle + 1 } else { high = middle }
            }
            if low > 0 { previous[index] = tails[low - 1] }
            if low == tails.count { tails.append(index) } else { tails[low] = index }
        }
        var result = Set<Int>()
        var index = tails.last ?? -1
        while index >= 0 {
            result.insert(index)
            index = previous[index]
        }
        return result
    }
}
