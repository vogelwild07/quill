import Foundation

/// Sprachen der Oberfläche (ADR-038). Was Quill selbst in den Store schreibt und später
/// über den Text wiederfindet (Sammelseite „Tage“, Tagesseite), sucht es in jeder Sprache
/// der App: Ein Sprachwechsel oder ein zweiter Mac mit anderer Sprache legt kein zweites
/// „Days“ an.
enum AppLanguages {
    /// Sprachen der App, die vom System gewählte zuerst.
    static var codes: [String] {
        let current = Bundle.module.preferredLocalizations.first ?? "de"
        let others = Bundle.module.localizations.filter { $0 != current && $0 != "Base" }.sorted()
        return [current] + others
    }

    /// Text zum Schlüssel in jeder der Sprachen, ohne Doppelte, Reihenfolge wie `codes`.
    static func texts(_ key: String.LocalizationValue, codes: [String] = codes) -> [String] {
        var texts: [String] = []
        for code in codes {
            var resource = LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
            resource.locale = Locale(identifier: code)
            let text = String(localized: resource)
            if !texts.contains(text) { texts.append(text) }
        }
        return texts
    }

    /// `locale` und dieselbe Region in jeder anderen der Sprachen, für Texte mit Datum.
    static func locales(from locale: Locale, codes: [String] = codes) -> [Locale] {
        let current = locale.language.languageCode?.identifier
        let others = codes.filter { $0 != current }.map { code in
            Locale(components: Locale.Components(languageCode: Locale.LanguageCode(code), languageRegion: locale.region))
        }
        return [locale] + others
    }
}
