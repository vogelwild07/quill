import Foundation
import QuillModel

extension InlineText {
    /// Runs für `Block.richText`; `nil`, wenn der Text unformatiert ist.
    public var richText: RichText? {
        guard !spans.isEmpty else { return nil }
        let utf16 = Array(text.utf16)
        var runs: [RichText.Run] = []
        var cursor = 0
        func piece(_ range: Range<Int>) -> String { String(decoding: utf16[range], as: UTF16.self) }
        for span in spans {
            if cursor < span.range.lowerBound { runs.append(.init(text: piece(cursor..<span.range.lowerBound))) }
            runs.append(.init(text: piece(span.range), marks: span.style.marks.map(\.rawValue), link: span.style.link))
            cursor = span.range.upperBound
        }
        if cursor < utf16.count { runs.append(.init(text: piece(cursor..<utf16.count))) }
        return RichText(runs: runs)
    }

    /// Liest Text und Formatierung. Passt `richText` nicht zu `text`, gilt nur `text`.
    public init(text: String, richText: RichText?) {
        guard let richText, richText.plainText == text else {
            self.init(text)
            return
        }
        var spans: [InlineSpan] = []
        var offset = 0
        for run in richText.runs {
            let length = run.text.utf16.count
            spans.append(InlineSpan(offset..<(offset + length), marks: Set(run.marks.map(InlineMark.init(rawValue:))), link: run.link))
            offset += length
        }
        self.init(text, spans: spans)
    }
}
