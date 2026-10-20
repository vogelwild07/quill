import Foundation
import QuillModel

/// Dreiwege-Abgleich der Blöcke einer Seite: `base` ist der Stand, den der Editor
/// zuletzt geladen oder gespeichert hat, `local` der Editor jetzt, `remote` der Store
/// jetzt (z. B. nach einem Abgleich des Sync oder dem Speichern eines anderen Fensters).
///
/// Nie still verwerfen (ADR-026): Was nur eine Seite geändert hat, gilt. Haben beide
/// denselben Block geändert, werden Art, Felder und Text getrennt zusammengeführt;
/// Text und Formatierung, solange sich die geänderten Stellen nicht überschneiden.
/// Sonst bleibt der lokale Block, und die Fassung aus dem Store steht als Kopie
/// dahinter, markiert als wiederhergestellt. Gelöscht gegen bearbeitet: Der
/// bearbeitete Block bleibt, ebenfalls markiert.
public enum BlockMerge {
    static func merge(base: [EditorBlock], local: [EditorBlock], remote: [EditorBlock]) -> [EditorBlock] {
        let baseByID = byID(base), localByID = byID(local), remoteByID = byID(remote)
        var kept: [UUID: [EditorBlock]] = [:]
        for id in Set(localByID.keys).union(remoteByID.keys) {
            let original = baseByID[id]
            switch (localByID[id], remoteByID[id]) {
            case let (mine?, theirs?):
                kept[id] = mergeBlock(base: original, local: mine, remote: theirs)
            case let (mine?, nil):
                // Im Store gelöscht: bleibt, wenn der Editor ihn geändert oder neu hat.
                if let original { if mine != original { kept[id] = [restored(mine)] } } else { kept[id] = [mine] }
            case let (nil, theirs?):
                // Im Editor gelöscht: bleibt, wenn er im Store geändert oder neu ist.
                if let original { if theirs != original { kept[id] = [restored(theirs)] } } else { kept[id] = [theirs] }
            case (nil, nil):
                break
            }
        }
        return order(base: base, local: local, remote: remote, kept: Set(kept.keys)).flatMap { kept[$0] ?? [] }
    }

    // MARK: Ein Block

    private static func mergeBlock(base: EditorBlock?, local: EditorBlock, remote: EditorBlock) -> [EditorBlock] {
        if local == remote { return [local] }
        guard let base else { return [local, copy(of: remote)] }
        if local == base { return [remote] }
        if remote == base { return [local] }
        guard let kind = pick(base.kind, local.kind, remote.kind),
              let properties = mergeProperties(base.properties, local.properties, remote.properties),
              let content = mergeContent(base.content, local.content, remote.content)
        else {
            return [local, copy(of: remote)]
        }
        var merged = local
        merged.kind = kind
        merged.content = content
        merged.properties = properties.normalized(for: kind)
        return [merged]
    }

    /// Der Wert der Seite, die ihn geändert hat; `nil`, wenn beide verschieden geändert haben.
    private static func pick<Value: Equatable>(_ base: Value, _ local: Value, _ remote: Value) -> Value? {
        if local == remote || remote == base { return local }
        if local == base { return remote }
        return nil
    }

    /// Jedes Feld einzeln (ADR-014); `BlockMergeTests.everyBlockFieldIsMerged` prüft
    /// das mit `SampleDocuments.fullProperties`.
    static func mergeProperties(
        _ base: BlockProperties, _ local: BlockProperties, _ remote: BlockProperties
    ) -> BlockProperties? {
        var result = local
        func field<Value: Equatable>(_ path: WritableKeyPath<BlockProperties, Value>) -> Bool {
            guard let value = pick(base[keyPath: path], local[keyPath: path], remote[keyPath: path]) else { return false }
            result[keyPath: path] = value
            return true
        }
        guard field(\.indent), field(\.isChecked), field(\.codeLanguage), field(\.assetID), field(\.isRestored) else {
            return nil
        }
        return result
    }

    private static func restored(_ block: EditorBlock) -> EditorBlock {
        var block = block
        block.isRestored = true
        return block
    }

    private static func copy(of block: EditorBlock) -> EditorBlock {
        restored(block.withNewID())
    }

    // MARK: Text

    /// Ein UTF-16-Zeichen mit seiner Formatierung.
    private struct Unit: Equatable {
        var code: UInt16
        var style: InlineStyle
    }

    /// Eine Änderung gegenüber `base`: `range` in `base` wird durch `replacement` ersetzt.
    private struct Edit: Equatable {
        var range: Range<Int>
        var replacement: [Unit]
    }

    static func mergeContent(_ base: InlineText, _ local: InlineText, _ remote: InlineText) -> InlineText? {
        if local == remote || remote == base { return local }
        if local == base { return remote }
        let original = units(base)
        let mine = edit(from: original, to: units(local))
        let theirs = edit(from: original, to: units(remote))
        let first: Edit, second: Edit
        if mine.range.upperBound <= theirs.range.lowerBound {
            (first, second) = (mine, theirs)
        } else if theirs.range.upperBound <= mine.range.lowerBound {
            (first, second) = (theirs, mine)
        } else {
            return nil
        }
        // Beide fügen an derselben Stelle ein: erst die lokale Eingabe, dann die andere.
        let result = Array(original[..<first.range.lowerBound]) + first.replacement
            + Array(original[first.range.upperBound..<second.range.lowerBound]) + second.replacement
            + Array(original[second.range.upperBound...])
        return text(from: result)
    }

    private static func units(_ text: InlineText) -> [Unit] {
        var result = text.text.utf16.map { Unit(code: $0, style: InlineStyle()) }
        for span in text.spans {
            for index in span.range where result.indices.contains(index) { result[index].style = span.style }
        }
        return result
    }

    /// Kleinste zusammenhängende Änderung (gemeinsamer Anfang und gemeinsames Ende),
    /// an Grenzen von Unicode-Skalaren, damit kein Ersatzpaar halbiert wird.
    private static func edit(from base: [Unit], to other: [Unit]) -> Edit {
        var prefix = 0
        while prefix < base.count, prefix < other.count, base[prefix] == other[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < base.count - prefix, suffix < other.count - prefix,
              base[base.count - 1 - suffix] == other[other.count - 1 - suffix] {
            suffix += 1
        }
        if prefix > 0, UTF16.isLeadSurrogate(base[prefix - 1].code) { prefix -= 1 }
        if suffix > 0, UTF16.isTrailSurrogate(base[base.count - suffix].code) { suffix -= 1 }
        return Edit(range: prefix..<(base.count - suffix), replacement: Array(other[prefix..<(other.count - suffix)]))
    }

    private static func text(from units: [Unit]) -> InlineText? {
        guard !units.isEmpty else { return InlineText() }
        let string = String(decoding: units.map(\.code), as: UTF16.self)
        guard string.utf16.count == units.count else { return nil }
        var spans: [InlineSpan] = []
        var start = 0
        for index in 1...units.count where index == units.count || units[index].style != units[start].style {
            if !units[start].style.isPlain { spans.append(InlineSpan(start..<index, units[start].style)) }
            start = index
        }
        return InlineText(string, spans: spans)
    }

    /// Wohin ein Cursor (UTF-16-Offset) wandert, wenn `old` zu `new` wird: vor der
    /// geänderten Stelle bleibt er, dahinter hält er den Abstand zum Ende, darin
    /// kommt er ans Ende der Änderung.
    public static func mappedOffset(_ offset: Int, from old: String, to new: String) -> Int {
        let old = Array(old.utf16), new = Array(new.utf16)
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }
        if offset <= prefix { return min(offset, new.count) }
        if offset >= old.count - suffix { return max(0, new.count - (old.count - offset)) }
        return new.count - suffix
    }

    // MARK: Reihenfolge

    /// Hat der Editor die gemeinsamen Blöcke umgestellt, gilt seine Reihenfolge, sonst
    /// die des Stores. Blöcke, die nur die andere Seite hat, kommen hinter ihren
    /// Vorgänger von dort.
    private static func order(base: [EditorBlock], local: [EditorBlock], remote: [EditorBlock], kept: Set<UUID>) -> [UUID] {
        let localIDs = unique(local.map(\.id)), remoteIDs = unique(remote.map(\.id))
        let common = Set(base.map(\.id)).intersection(localIDs).intersection(remoteIDs)
        let movedLocally = localIDs.filter(common.contains) != unique(base.map(\.id)).filter(common.contains)
        let (lead, other) = movedLocally ? (localIDs, remoteIDs) : (remoteIDs, localIDs)
        var result = lead.filter(kept.contains)
        var placed = Set(result)
        for (index, id) in other.enumerated() where kept.contains(id) && !placed.contains(id) {
            if let predecessor = other[..<index].last(where: placed.contains), let position = result.firstIndex(of: predecessor) {
                result.insert(id, at: position + 1)
            } else if let successor = other[(index + 1)...].first(where: placed.contains), let position = result.firstIndex(of: successor) {
                result.insert(id, at: position)
            } else {
                result.append(id)
            }
            placed.insert(id)
        }
        return result
    }

    private static func byID(_ blocks: [EditorBlock]) -> [UUID: EditorBlock] {
        Dictionary(blocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
