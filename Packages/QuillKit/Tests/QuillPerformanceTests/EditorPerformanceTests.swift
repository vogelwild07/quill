#if canImport(AppKit)
import AppKit
import Testing

extension PerformanceSuites {
    /// Laden, Tippen und Enter bei 1000 Blöcken (Produktziele: Laden < 300 ms,
    /// Tippen und Enter p95 < 16 ms, ADR-007).
    @MainActor
    @Suite("Editor")
    struct Editor {
        @Test func loadTypingEnter() {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
            var results: [EditorBenchmark.Result] = []
            _ = EditorBenchmark.run(in: window, blockCount: 1000, keystrokes: 200, enters: 50)
            for _ in 0..<Performance.runs {
                results.append(EditorBenchmark.run(in: window, blockCount: 1000, keystrokes: 200, enters: 50))
            }
            #expect(results.allSatisfy { $0.blocks == 1050 })
            Performance.report("editorLoad", runs: results.map(\.loadMilliseconds))
            Performance.report("editorTyping", runs: results.map(\.typing.p95))
            Performance.report("editorEnter", runs: results.map(\.enter.p95))
        }
    }
}
#endif
