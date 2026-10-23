import Foundation
import QuillModel

/// „Ablage › Heute“ (15.5, ADR-033): Seite des Tages unter der Sammelseite „Tage“,
/// gefunden über den Titel, bei Bedarf angelegt.
public struct TodayPage: Sendable {
    let store: PageStore

    public init(store: PageStore) {
        self.store = store
    }

    /// Titel der Sammelseite auf der obersten Ebene.
    static var containerTitle: String { String(localized: "Tage", bundle: .module) }

    /// Titel der Tagesseite, z. B. „Freitag, 23. Oktober 2026“.
    static func title(for date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        style = style.weekday(.wide).day().month(.wide).year()
        return date.formatted(style)
    }

    /// Kennung der Tagesseite; fehlt sie, kommt sie oben in „Tage“ dazu, der neueste Tag zuerst.
    public func open(now: Date = .now, locale: Locale = .current, calendar: Calendar = .current) async throws -> UUID {
        let containerTitle = Self.containerTitle
        let container: UUID
        if let existing = try await store.activeChild(titled: containerTitle, in: nil) {
            container = existing
        } else {
            container = try await store.createPage(title: containerTitle)
        }
        let title = Self.title(for: now, locale: locale, calendar: calendar)
        if let day = try await store.activeChild(titled: title, in: container) {
            return day
        }
        return try await store.createPage(title: title, in: container, at: .first)
    }
}
