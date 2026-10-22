import Foundation
import Testing

/// Gemeinsame Regeln der Performance-Messungen (`docs/performance.md`).
///
/// - Nur in optimierten Builds (`swift test -c release`); in Debug übersprungen.
/// - Pro Messung ein Aufwärmlauf, dann `runs` Läufe. Ein Lauf ergibt einen Wert (bei
///   mehreren Proben dessen p95), verglichen wird der Median der Läufe.
/// - Jede Messung schreibt eine Zeile `PERF <Name> <ms>` für `Scripts/perf-package.py`.
enum Performance {
    static let isOptimized: Bool = {
        #if DEBUG
        false
        #else
        true
        #endif
    }()

    static let runs = 5

    /// Obergrenzen in Millisekunden. Produktziele fest, sonst Baseline × 3, mindestens
    /// Baseline + 5 ms, nie über dem Produktziel (Werte: `docs/performance.md`).
    static let limits: [String: Double] = [
        // Produktziele
        "editorLoad": 300,
        "editorTyping": 16,
        "editorEnter": 16,
        "search": 100,
        "exportPlan": 2000,
        "historyDays": 250, // Zeitreise öffnen, ADR-031
        "historyDayBlocks": 300, // wie Laden im Editor
        // Baseline 19.10.2026 × 3, gerundet nach oben
        "applyEditsMove": 178,
        "applyEditsReverse": 309,
        "bridgeLoad": 300, // 3 × 106 = 319, gedeckelt durch Produktziel Laden
        "pageTreeBuild": 175, // 5000 Seiten; Sidebar-Ziel 100 ms gilt für 1000 (App-Messung)
    ]

    /// p95 einer Probe (nächstgelegener Rang).
    static func p95(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// Meldet den Median der Läufe und prüft ihn gegen die Schwelle.
    static func report(_ name: String, runs values: [Double], sourceLocation: SourceLocation = #_sourceLocation) {
        let value = median(values)
        let formatted = String(format: "%.2f", value)
        print("PERF \(name) \(formatted)")
        guard let limit = limits[name] else {
            Issue.record("Keine Schwelle für \(name) (\(formatted) ms)", sourceLocation: sourceLocation)
            return
        }
        #expect(value < limit, "\(name): \(formatted) ms, Schwelle \(limit) ms", sourceLocation: sourceLocation)
    }

    /// Aufwärmlauf plus `runs` Läufe; `body` liefert den Wert eines Laufs.
    static func repeated(_ body: () throws -> Double) rethrows -> [Double] {
        _ = try body()
        return try (0..<runs).map { _ in try body() }
    }

    static func repeated(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> Double
    ) async rethrows -> [Double] {
        _ = try await body()
        var values: [Double] = []
        for _ in 0..<runs { values.append(try await body()) }
        return values
    }
}

/// Alle Messungen nacheinander, damit sie sich nicht gegenseitig bremsen.
@Suite("Performance (Release)", .serialized, .enabled(if: Performance.isOptimized, "nur mit swift test -c release"))
enum PerformanceSuites {}
