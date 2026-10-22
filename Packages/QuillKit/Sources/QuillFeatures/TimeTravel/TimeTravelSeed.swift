#if DEBUG
import Foundation
import QuillModel
import QuillSync

/// Nur für UI-Tests (`-QuillSeedTimeTravel YES`, nur mit Test-Store): eine Seite
/// „Zeitreise-Test“ mit Geschichte über drei Tage, damit die Zeitreise frühere Tage zeigt
/// (`TimeTravelUITests`). Vorgestern „Erster Absatz“ und „Alter Absatz“, gestern
/// „Erster Absatz“ und „Gestern geschrieben“, heute nur „Erster Absatz“.
enum TimeTravelSeed {
    static let title = "Zeitreise-Test"

    /// Gibt die ID der Seite zurück.
    @discardableResult
    static func write(to store: PageStore, now: Date = Date()) async throws -> UUID {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func noon(daysAgo: Int) -> Date {
            calendar.date(byAdding: DateComponents(day: -daysAgo, hour: 12), to: today)!
        }
        let first = BlockSnapshot(id: UUID(), text: "Erster Absatz")
        let old = BlockSnapshot(id: UUID(), text: "Alter Absatz")
        let yesterday = BlockSnapshot(id: UUID(), text: "Gestern geschrieben")
        let document = try PageHistory.testDocument([
            (noon(daysAgo: 2), [first, old]),
            (noon(daysAgo: 1), [first, yesterday]),
            (min(now, noon(daysAgo: 0)), [first]),
        ])
        let page = try await store.createPage(title: title)
        try await store.applyEdits(page, BlockEdits(upserts: [first], order: [first.id]))
        _ = try await store.saveHistory(page, document: document)
        return page
    }
}
#endif
