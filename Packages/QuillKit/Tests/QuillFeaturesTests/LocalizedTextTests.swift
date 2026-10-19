import Foundation
import QuillModel
import Testing
@testable import QuillFeatures

/// Texte aus dem Katalog zur Laufzeit: Pluralformen und Fehler beim Öffnen
/// (Phase 7.3). Dass jeder Schlüssel im Katalog steht, prüft `LocalizationTests`.
@MainActor
@Suite("Lokalisierung: Texte zur Laufzeit")
struct LocalizedTextTests {
    @Test func pluralFormsResolve() {
        #expect(String(localized: "\(1) Seiten endgültig löschen?", bundle: .module) == "1 Seite endgültig löschen?")
        #expect(String(localized: "\(3) Seiten endgültig löschen?", bundle: .module) == "3 Seiten endgültig löschen?")
        #expect(String(localized: "Seiten werden nach \(1) Tagen endgültig gelöscht.", bundle: .module) == "Seiten werden nach 1 Tag endgültig gelöscht.")
        #expect(String(localized: "Seiten werden nach \(30) Tagen endgültig gelöscht.", bundle: .module) == "Seiten werden nach 30 Tagen endgültig gelöscht.")
    }

    @Test func storeLayoutErrorsAreLocalized() {
        #expect(PersistenceErrorView.detail(for: StoreLayoutError.locked) == "Eine andere Quill-Instanz richtet gerade die Datenbank ein.")
        #expect(PersistenceErrorView.detail(for: StoreLayoutError.moveConflict("/a/b")) == "Umzug angehalten, im Ziel liegt schon: /a/b")
        struct Other: Error {}
        #expect(PersistenceErrorView.detail(for: Other()) == String(describing: Other()))
    }
}
