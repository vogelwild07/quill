import Foundation
import QuillEditorCore
import QuillModel

/// Folien einer Seite (18.2, ADR-035): Jede Überschrift der obersten Ebene, die auf der
/// Seite vorkommt, beginnt eine Folie. Die erste Folie zeigt den Titel und alles vor der
/// ersten trennenden Überschrift; ohne Überschriften ist die ganze Seite eine Folie.
enum SlideDeck {
    /// Nie leer; jede Folie hat mindestens einen Block.
    static func slides(title: String, blocks: [EditorBlock]) -> [[EditorBlock]] {
        let split = [BlockKind.heading1, .heading2, .heading3].first { level in blocks.contains { $0.kind == level } }
        var slides = [[EditorBlock(kind: .heading1, text: title)]]
        for block in blocks {
            if block.kind == split {
                slides.append([block])
            } else {
                slides[slides.count - 1].append(block)
            }
        }
        return slides
    }
}
