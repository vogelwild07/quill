import Foundation
import QuillModel
import Testing
@testable import QuillFeatures

/// Texte aus dem Katalog zur Laufzeit: Pluralformen und Fehler beim Öffnen
/// (Phase 7.3). Dass jeder Schlüssel im Katalog steht, prüft `LocalizationTests`.
///
/// Package-Tests laufen auf Englisch: Pakete folgen der Sprache des Hauptprogramms, und der
/// Testrunner (`swift test`, `xctest`) hat keine Sprachen (ADR-038). Erwartungen in den
/// Package-Tests sind deshalb englisch; Deutsch prüfen die UI-Tests (fest auf Deutsch) und
/// hier `text(_:in:)` ausdrücklich.
@MainActor
@Suite("Lokalisierung: Texte zur Laufzeit")
struct LocalizedTextTests {
    /// Text aus dem Katalog von QuillFeatures in einer bestimmten Sprache.
    func text(_ key: String.LocalizationValue, in language: String) -> String {
        var resource = LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
        resource.locale = Locale(identifier: language)
        return String(localized: resource)
    }

    /// Ändert sich die Sprache des Testrunners, schlagen viele Tests mit deutschen statt
    /// englischen Texten fehl; dieser sagt warum.
    @Test func packageTestsRunInEnglish() {
        #expect(Bundle.module.preferredLocalizations.first == "en",
                "Testrunner nicht mehr auf Englisch: Erwartungen der Package-Tests anpassen (ADR-038)")
        #expect(Set(Bundle.module.localizations) == ["de", "en"])
    }

    @Test func pluralFormsResolve() {
        #expect(text("\(1) Seiten endgültig löschen?", in: "de") == "1 Seite endgültig löschen?")
        #expect(text("\(3) Seiten endgültig löschen?", in: "de") == "3 Seiten endgültig löschen?")
        #expect(text("Seiten werden nach \(1) Tagen endgültig gelöscht.", in: "de") == "Seiten werden nach 1 Tag endgültig gelöscht.")
        #expect(text("Seiten werden nach \(30) Tagen endgültig gelöscht.", in: "de") == "Seiten werden nach 30 Tagen endgültig gelöscht.")
        #expect(text("\(1) Seiten endgültig löschen?", in: "en") == "Permanently delete 1 page?")
        #expect(text("\(3) Seiten endgültig löschen?", in: "en") == "Permanently delete 3 pages?")
        #expect(String(localized: "Seiten werden nach \(1) Tagen endgültig gelöscht.", bundle: .module) == "Pages are permanently deleted after 1 day.")
        #expect(String(localized: "Seiten werden nach \(30) Tagen endgültig gelöscht.", bundle: .module) == "Pages are permanently deleted after 30 days.")
    }

    /// Platzhalter in anderer Reihenfolge oder Position (`%1$@`) kommen richtig an.
    @Test func placeholdersKeepTheirOrder() {
        #expect(text("Zu wenig freier Speicher: \("1 GB") nötig, \("2 GB") frei.", in: "en") == "Not enough free space: 1 GB needed, 2 GB available.")
        #expect(text("Folie \(2) von \(5)", in: "en") == "Slide 2 of 5")
        #expect(text("Folie \(2) von \(5)", in: "de") == "Folie 2 von 5")
    }

    @Test func storeLayoutErrorsAreLocalized() {
        #expect(PersistenceErrorView.detail(for: StoreLayoutError.locked) == "Another instance of Quill is setting up the database right now.")
        #expect(PersistenceErrorView.detail(for: StoreLayoutError.moveConflict("/a/b")) == "Move stopped, the destination already contains: /a/b")
        struct Other: Error {}
        #expect(PersistenceErrorView.detail(for: Other()) == String(describing: Other()))
    }
}
