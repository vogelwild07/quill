#if canImport(AppKit)
import AppKit

/// Messung Laden, Tippen und Enter bei vielen Blöcken (Spike-Kriterium 1, ADR-007).
/// Läuft im Performance-Test und mit `-benchmark` im Release-Build.
@MainActor
public enum EditorBenchmark {
    public struct Result: Codable, Sendable {
        public var blocks: Int
        public var loadMilliseconds: Double
        public var typing: Stats
        public var enter: Stats
    }

    public struct Stats: Codable, Sendable {
        public var samples: Int
        public var median: Double
        public var p95: Double
        public var max: Double

        init(_ values: [Double]) {
            let sorted = values.sorted()
            samples = sorted.count
            median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
            p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            max = sorted.last ?? 0
        }
    }

    /// Lädt ein großes Dokument in `window`, tippt in die Mitte und misst pro Tastendruck
    /// Einfügen + Modellabgleich + Layout + Zeichnen des sichtbaren Bereichs.
    public static func run(in window: NSWindow, blockCount: Int = 1000, keystrokes: Int = 200, enters: Int = 50) -> Result {
        let document = sampleDocument(blockCount: blockCount)

        let loadStart = ContinuousClock.now
        let controller = BlockEditorController(document: document)
        window.contentView = controller.scrollView
        controller.focus()
        forceLayoutAndDisplay(controller)
        let load = milliseconds(since: loadStart)

        let target = (blockCount / 2..<document.count).first { document[$0].kind == .paragraph } ?? 0
        let middle = controller.characterLocation(of: BlockPosition(block: target, offset: 10))
        controller.textView.setSelectedRange(NSRange(location: middle, length: 0))
        controller.textView.scrollRangeToVisible(NSRange(location: middle, length: 0))
        forceLayoutAndDisplay(controller)

        var typing: [Double] = []
        for index in 0..<keystrokes {
            let start = ContinuousClock.now
            controller.textView.insertText(index % 7 == 6 ? " " : "x", replacementRange: controller.textView.selectedRange())
            forceLayoutAndDisplay(controller)
            typing.append(milliseconds(since: start))
        }

        var enter: [Double] = []
        for _ in 0..<enters {
            let start = ContinuousClock.now
            controller.textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            forceLayoutAndDisplay(controller)
            enter.append(milliseconds(since: start))
        }

        return Result(blocks: controller.document.count, loadMilliseconds: load, typing: Stats(typing), enter: Stats(enter))
    }

    /// Großes Dokument mit gemischten Blockarten.
    public static func sampleDocument(blockCount: Int) -> EditorDocument {
        let sentence = "Quill speichert lokal, startet schnell und hält den Text im Mittelpunkt. "
        var blocks: [EditorBlock] = []
        blocks.reserveCapacity(blockCount)
        for index in 0..<blockCount {
            switch index % 20 {
            case 0: blocks.append(EditorBlock(kind: .heading2, text: "Abschnitt \(index / 20 + 1)"))
            case 1...3: blocks.append(EditorBlock(kind: .bulleted, text: "Punkt \(index)", indent: index % 2))
            case 4...6: blocks.append(EditorBlock(kind: .numbered, text: "Schritt \(index)"))
            case 7, 8: blocks.append(EditorBlock(kind: .todo, text: "Aufgabe \(index)", isChecked: index % 2 == 0))
            case 9: blocks.append(EditorBlock(kind: .quote, text: sentence))
            case 10: blocks.append(EditorBlock(kind: .code, text: "func f\(index)() {\n    return\n}", codeLanguage: "swift"))
            default: blocks.append(EditorBlock(text: String(repeating: sentence, count: 1 + index % 3)))
            }
        }
        return EditorDocument(blocks: blocks)
    }

    private static func forceLayoutAndDisplay(_ controller: BlockEditorController) {
        let textView = controller.textView
        if let manager = textView.textLayoutManager {
            manager.textViewportLayoutController.layoutViewport()
        }
        textView.displayIfNeeded()
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}
#endif
