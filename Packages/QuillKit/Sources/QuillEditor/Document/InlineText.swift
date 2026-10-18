import Foundation

/// Inline-Formatierung. String-Rohwert wie `kindRaw`: Unbekannte Marks späterer
/// Versionen bleiben erhalten, werden aber nicht dargestellt.
public struct InlineMark: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let bold = InlineMark(rawValue: "bold")
    public static let italic = InlineMark(rawValue: "italic")
    public static let code = InlineMark(rawValue: "code")
    public static let strikethrough = InlineMark(rawValue: "strikethrough")

    public static func < (lhs: InlineMark, rhs: InlineMark) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Formatierung eines Textstücks: Marks und optional ein Link.
public struct InlineStyle: Hashable, Codable, Sendable {
    public var marks: Set<InlineMark>
    /// Link-Ziel als Text, unverändert gespeichert (auch wenn es keine gültige URL ist).
    public var link: String?

    public init(marks: Set<InlineMark> = [], link: String? = nil) {
        self.marks = marks
        self.link = link
    }

    public var isPlain: Bool { marks.isEmpty && link == nil }
}

/// Formatierter Bereich eines Blocktexts in UTF-16-Einheiten.
public struct InlineSpan: Equatable, Codable, Sendable {
    public var range: Range<Int>
    public var style: InlineStyle

    public init(_ range: Range<Int>, _ style: InlineStyle) {
        self.range = range
        self.style = style
    }

    public init(_ range: Range<Int>, marks: Set<InlineMark>, link: String? = nil) {
        self.init(range, InlineStyle(marks: marks, link: link))
    }
}

/// Text mit Formatierung. Werttyp für Teilen, Verbinden und Formatieren.
///
/// Invariante (`normalized`): Spans sind sortiert, überlappen nicht, sind nicht
/// leer, nicht unformatiert und liegen innerhalb des Texts; aneinanderstoßende
/// Spans mit gleichem Stil sind zusammengefasst.
public struct InlineText: Equatable, Sendable {
    public var text: String
    public var spans: [InlineSpan]

    public init(_ text: String = "", spans: [InlineSpan] = []) {
        self.text = text
        self.spans = Self.normalized(spans, length: text.utf16.count)
    }

    public var length: Int { text.utf16.count }

    /// Teilt an einem UTF-16-Offset.
    public func split(at offset: Int) -> (InlineText, InlineText) {
        let (head, tail) = EditorDocument.split(text, at: offset)
        let cut = head.utf16.count
        let headSpans = spans.compactMap { span -> InlineSpan? in
            let range = span.range.clamped(to: 0..<cut)
            return range.isEmpty ? nil : InlineSpan(range, span.style)
        }
        let tailSpans = spans.compactMap { span -> InlineSpan? in
            let range = span.range.clamped(to: cut..<Int.max)
            return range.isEmpty ? nil : InlineSpan((range.lowerBound - cut)..<(range.upperBound - cut), span.style)
        }
        return (InlineText(head, spans: headSpans), InlineText(tail, spans: tailSpans))
    }

    public static func + (lhs: InlineText, rhs: InlineText) -> InlineText {
        let offset = lhs.length
        let shifted = rhs.spans.map { InlineSpan(($0.range.lowerBound + offset)..<($0.range.upperBound + offset), $0.style) }
        return InlineText(lhs.text + rhs.text, spans: lhs.spans + shifted)
    }

    /// Stil am Zeichen bei `offset` (unformatiert, wenn kein Span es abdeckt).
    public func style(at offset: Int) -> InlineStyle {
        spans.first { $0.range.contains(offset) }?.style ?? InlineStyle()
    }

    /// `true`, wenn jedes Zeichen in `range` die Mark trägt.
    public func hasMark(_ mark: InlineMark, in range: Range<Int>) -> Bool {
        var covered = range.lowerBound
        for span in spans where span.style.marks.contains(mark) && span.range.overlaps(range) {
            guard span.range.lowerBound <= covered else { return false }
            covered = max(covered, span.range.upperBound)
        }
        return covered >= range.upperBound
    }

    public mutating func setMark(_ mark: InlineMark, _ isOn: Bool, in range: Range<Int>) {
        restyle(range) { style in
            if isOn { style.marks.insert(mark) } else { style.marks.remove(mark) }
        }
    }

    /// `nil` entfernt den Link.
    public mutating func setLink(_ link: String?, in range: Range<Int>) {
        restyle(range) { $0.link = link }
    }

    /// Zusammenhängender Bereich mit demselben Link um `offset`.
    public func linkRange(at offset: Int) -> (range: Range<Int>, link: String)? {
        guard let span = spans.first(where: { $0.range.contains(offset) && $0.style.link != nil }),
              let link = span.style.link else { return nil }
        var lower = span.range.lowerBound
        var upper = span.range.upperBound
        for other in spans.reversed() where other.range.upperBound == lower && other.style.link == link {
            lower = other.range.lowerBound
        }
        for other in spans where other.range.lowerBound == upper && other.style.link == link {
            upper = other.range.upperBound
        }
        return (lower..<upper, link)
    }

    private mutating func restyle(_ range: Range<Int>, _ change: (inout InlineStyle) -> Void) {
        let range = range.clamped(to: 0..<length)
        guard !range.isEmpty else { return }
        var result: [InlineSpan] = []
        var cursor = range.lowerBound
        for span in spans {
            // Teile außerhalb bleiben, Teile innerhalb werden geändert.
            if span.range.lowerBound < range.lowerBound {
                result.append(InlineSpan(span.range.lowerBound..<min(span.range.upperBound, range.lowerBound), span.style))
            }
            let inside = span.range.clamped(to: range)
            if !inside.isEmpty {
                if cursor < inside.lowerBound {
                    var plain = InlineStyle()
                    change(&plain)
                    result.append(InlineSpan(cursor..<inside.lowerBound, plain))
                }
                var style = span.style
                change(&style)
                result.append(InlineSpan(inside, style))
                cursor = inside.upperBound
            }
            if span.range.upperBound > range.upperBound {
                result.append(InlineSpan(max(span.range.lowerBound, range.upperBound)..<span.range.upperBound, span.style))
            }
        }
        if cursor < range.upperBound {
            var plain = InlineStyle()
            change(&plain)
            result.append(InlineSpan(cursor..<range.upperBound, plain))
        }
        spans = Self.normalized(result, length: length)
    }

    /// Stellt die Invariante her. Überlappende Spans werden zerlegt; im Überlappungsbereich
    /// gelten die Marks beider und der Link des späteren.
    public static func normalized(_ spans: [InlineSpan], length: Int) -> [InlineSpan] {
        let clamped = spans.compactMap { span -> InlineSpan? in
            let range = span.range.clamped(to: 0..<max(0, length))
            return range.isEmpty || span.style.isPlain ? nil : InlineSpan(range, span.style)
        }
        guard !clamped.isEmpty else { return [] }

        let sorted = clamped.sorted { $0.range.lowerBound < $1.range.lowerBound }
        let needsSegmentation = zip(sorted, sorted.dropFirst()).contains { $0.range.upperBound > $1.range.lowerBound }
        var pieces = sorted
        if needsSegmentation {
            let bounds = Set(clamped.flatMap { [$0.range.lowerBound, $0.range.upperBound] }).sorted()
            pieces = []
            for (lower, upper) in zip(bounds, bounds.dropFirst()) {
                var style = InlineStyle()
                for span in clamped where span.range.lowerBound <= lower && span.range.upperBound >= upper {
                    style.marks.formUnion(span.style.marks)
                    if let link = span.style.link { style.link = link }
                }
                if !style.isPlain { pieces.append(InlineSpan(lower..<upper, style)) }
            }
        }

        var merged: [InlineSpan] = []
        for piece in pieces {
            if let last = merged.last, last.range.upperBound == piece.range.lowerBound, last.style == piece.style {
                merged[merged.count - 1].range = last.range.lowerBound..<piece.range.upperBound
            } else {
                merged.append(piece)
            }
        }
        return merged
    }
}
