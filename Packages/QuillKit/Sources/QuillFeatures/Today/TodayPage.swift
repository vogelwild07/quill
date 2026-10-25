import Foundation
import QuillModel

/// „Ablage › Heute“ (15.5, ADR-033): Seite des Tages unter der Sammelseite „Tage“,
/// gefunden über den Titel, bei Bedarf angelegt.
public struct TodayPage: Sendable {
    let store: PageStore

    public init(store: PageStore) {
        self.store = store
    }

    /// Titel der Sammelseite auf der obersten Ebene in jeder Sprache der App, die aktuelle
    /// zuerst (ADR-038).
    static func containerTitles(languages: [String] = AppLanguages.codes) -> [String] {
        AppLanguages.texts("Tage", codes: languages)
    }

    /// Titel der Tagesseite, z. B. „Freitag, 23. Oktober 2026“.
    static func title(for date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        style = style.weekday(.wide).day().month(.wide).year()
        return date.formatted(style)
    }

    /// Kennung der Tagesseite; fehlt sie, kommt sie oben in „Tage“ dazu, der neueste Tag zuerst.
    /// Sammelseite und Tag findet Quill in jeder Sprache der App; neu angelegt wird in der
    /// aktuellen (`languages.first`, Datum mit `locale`).
    public func open(now: Date = .now, locale: Locale = .current, calendar: Calendar = .current) async throws -> UUID {
        try await open(now: now, locale: locale, calendar: calendar, languages: AppLanguages.codes)
    }

    func open(now: Date, locale: Locale, calendar: Calendar, languages: [String]) async throws -> UUID {
        let containerTitles = Self.containerTitles(languages: languages)
        let container: UUID
        if let existing = try await firstChild(titled: containerTitles, in: nil) {
            container = existing
        } else {
            container = try await store.createPage(title: containerTitles[0])
        }
        let titles = AppLanguages.locales(from: locale, codes: languages).map {
            Self.title(for: now, locale: $0, calendar: calendar)
        }
        if let day = try await firstChild(titled: titles, in: container) {
            return day
        }
        return try await store.createPage(title: titles[0], in: container, at: .first)
    }

    private func firstChild(titled titles: [String], in parent: UUID?) async throws -> UUID? {
        for title in titles {
            if let id = try await store.activeChild(titled: title, in: parent) { return id }
        }
        return nil
    }
}
