import Automerge
import Foundation
import QuillEditor
import QuillModel

/// Zufallszahlen mit fester Saat (SplitMix64), damit jeder Lauf dieselben Seiten
/// erzeugt.
public struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &self) < probability
    }
}

/// Wann ein Commit entsteht. Der Editor speichert 300 ms nach der letzten Eingabe
/// (`EditorPersistenceBridge`), beim normalen Tippen also etwa einmal pro Wort.
public enum CommitGranularity: String, Sendable, CaseIterable {
    case perWord = "pro Wort"
    case perKeystroke = "pro Tastendruck"
}

/// Schreibt eine Seite so, wie ein Mensch sie tippt: Zeichen für Zeichen, mit
/// Tippfehlern, die wieder gelöscht werden (etwa 10 % der Eingaben), Formatierung,
/// späteren Einschüben in ältere Blöcke, abgehakten To-dos und geänderten Blockarten.
/// Alle Texte sind erfunden (Silben aus einer festen Liste).
public struct PageHistorySimulator {
    public let words: Int
    public let granularity: CommitGranularity
    private var random: SeededRandom
    private var page: PageCRDT
    /// Textobjekte und Skalarlängen der Blöcke, damit nicht jeder Tastendruck den
    /// Block im Dokument sucht.
    private var texts: [ObjId] = []
    private var lengths: [Int] = []
    private var kinds: [BlockKind] = []
    private var written = 0
    public private(set) var keystrokes = 0
    public private(set) var deletions = 0

    public init(words: Int, granularity: CommitGranularity, seed: UInt64) throws {
        self.words = words
        self.granularity = granularity
        random = SeededRandom(seed: seed)
        page = try PageCRDT()
    }

    /// Schreibt die Seite und gibt sie zurück.
    public mutating func run() throws -> PageCRDT {
        while written < words {
            try writeBlock()
            if random.chance(0.1), texts.count > 2 { try reviseEarlierBlock() }
            if random.chance(0.02), !texts.isEmpty { try changeKind() }
        }
        page.document.commitWith()
        return page
    }

    private static let syllables = [
        "ber", "gen", "schaft", "lich", "un", "ter", "wal", "dung", "ein", "fach", "mor", "stra", "ße", "über",
        "lö", "sung", "kä", "se", "grü", "ne", "haus", "zeit", "ar", "beit", "no", "tiz", "sei", "te", "plan",
        "fen", "ster", "lin", "de", "wo", "che", "ru", "he", "mar", "kt", "schrei", "ben", "le", "sen",
    ]

    private mutating func word() -> String {
        var result = ""
        for _ in 0..<Int.random(in: 1...4, using: &random) {
            result += Self.syllables.randomElement(using: &random)!
        }
        if random.chance(0.15) { result = result.prefix(1).uppercased() + result.dropFirst() }
        // Selten ein Zeichen außerhalb der BMP, damit die Umrechnung in UTF-16 zählt.
        if random.chance(0.002) { result += "🙂" }
        return result
    }

    private mutating func nextKind() -> (BlockKind, ClosedRange<Int>) {
        switch Int.random(in: 0..<100, using: &random) {
        case 0..<55: (.paragraph, 20...80)
        case 55..<63: ([.heading1, .heading2, .heading3].randomElement(using: &random)!, 2...6)
        case 63..<75: (.bulleted, 3...15)
        case 75..<83: (.todo, 3...12)
        case 83..<88: (.numbered, 3...15)
        case 88..<93: (.quote, 10...40)
        case 93..<98: (.code, 5...30)
        default: (.divider, 0...0)
        }
    }

    private mutating func writeBlock() throws {
        let (kind, range) = nextKind()
        let index = texts.count
        let block = EditorBlock(
            kind: kind, indent: kind.isIndentable && random.chance(0.2) ? 1 : 0,
            codeLanguage: kind == .code ? "swift" : nil
        )
        texts.append(try page.insertBlock(block, at: index))
        lengths.append(0)
        kinds.append(kind)
        commitIfPerKeystroke()
        guard kind != .divider else {
            page.document.commitWith()
            return
        }
        let count = min(Int.random(in: range, using: &random), max(1, words - written))
        for number in 0..<count {
            try type(number == 0 ? word() : " " + word(), into: index)
            written += 1
        }
        if kind == .todo, random.chance(0.4) {
            try page.document.put(obj: page.map(at: index), key: "checked", value: .Boolean(true))
            page.document.commitWith()
        }
        if kind.allowsInlineMarks, random.chance(0.3), lengths[index] > 10 {
            try markRandomRange(in: index)
        }
    }

    /// Tippt Zeichen für Zeichen am Ende des Blocks; Tippfehler werden mit
    /// Rückschritt wieder gelöscht.
    private mutating func type(_ text: String, into index: Int) throws {
        try type(text, into: index, at: lengths[index])
    }

    private mutating func type(_ text: String, into index: Int, at start: Int) throws {
        var position = start
        // Bei etwa 40 % der Wörter 1–3 Fehlzeichen, die wieder gelöscht werden:
        // zusammen etwa 10 % aller Eingaben.
        if random.chance(0.4) {
            let typo = Int.random(in: 1...3, using: &random)
            for _ in 0..<typo { try insert("x", into: index, at: &position) }
            for _ in 0..<typo {
                position -= 1
                try page.document.spliceText(obj: texts[index], start: UInt64(position), delete: 1)
                lengths[index] -= 1
                deletions += 1
                commitIfPerKeystroke()
            }
        }
        for scalar in text.unicodeScalars {
            try insert(String(scalar), into: index, at: &position)
        }
        if granularity == .perWord { page.document.commitWith() }
    }

    private mutating func insert(_ character: String, into index: Int, at position: inout Int) throws {
        try page.document.spliceText(obj: texts[index], start: UInt64(position), delete: 0, value: character)
        position += 1
        lengths[index] += 1
        keystrokes += 1
        commitIfPerKeystroke()
    }

    private func commitIfPerKeystroke() {
        if granularity == .perKeystroke { page.document.commitWith() }
    }

    private mutating func markRandomRange(in index: Int) throws {
        let start = Int.random(in: 0..<(lengths[index] - 5), using: &random)
        let end = min(lengths[index], start + Int.random(in: 3...20, using: &random))
        let style: InlineStyle = switch Int.random(in: 0..<4, using: &random) {
        case 0: InlineStyle(marks: [.bold])
        case 1: InlineStyle(marks: [.italic])
        case 2: InlineStyle(marks: [.code])
        default: InlineStyle(link: "https://example.com/\(Int.random(in: 1...999, using: &random))")
        }
        try page.mark(texts[index], start: start, end: end, style: style)
        page.document.commitWith()
    }

    /// Ein paar Wörter mitten in einen älteren Block einfügen.
    private mutating func reviseEarlierBlock() throws {
        let candidates = texts.indices.filter { kinds[$0] != .divider && lengths[$0] > 0 }
        guard let index = candidates.randomElement(using: &random) else { return }
        let at = Int.random(in: 0...lengths[index], using: &random)
        var offset = at
        for _ in 0..<Int.random(in: 1...6, using: &random) {
            let piece = " " + word()
            try type(piece, into: index, at: offset)
            offset += piece.unicodeScalars.count
            written += 1
        }
    }

    private mutating func changeKind() throws {
        let index = Int.random(in: 0..<texts.count, using: &random)
        guard kinds[index] == .paragraph else { return }
        let kind: BlockKind = random.chance(0.5) ? .quote : .heading2
        kinds[index] = kind
        try page.document.put(obj: page.map(at: index), key: "kind", value: .String(kind.rawValue))
        page.document.commitWith()
    }
}
