import Foundation

/// Regeln für Updates (ADR-037), ohne Sparkle: woher und wie oft.
public enum UpdatePolicy {
    /// Versionsliste (Appcast) des neuesten Release; GitHub leitet auf die Datei im Release um.
    public static let feedURL = URL(string: "https://github.com/vogelwild07/quill/releases/latest/download/appcast.xml")!
    /// Höchstens so oft sucht Quill von selbst.
    public static let interval: TimeInterval = 24 * 60 * 60
    /// So oft prüft Quill, ob die nächste Suche fällig ist.
    public static let tick: TimeInterval = 60 * 60
    /// Pfad unter `github.com`, unter dem Feed und Archive liegen müssen.
    static let releasePath = ["/", "vogelwild07", "quill", "releases"]

    /// Automatisch nur, wenn eingeschaltet, und höchstens einmal am Tag. Liegt der letzte
    /// Versuch in der Zukunft (Uhr zurückgestellt), gilt er als alt.
    public static func mayCheckAutomatically(enabled: Bool, lastAttempt: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let lastAttempt, lastAttempt <= now else { return true }
        return now.timeIntervalSince(lastAttempt) >= interval
    }

    /// Feed und Archiv nur über HTTPS von `github.com/vogelwild07/quill/releases/…`, ohne
    /// Anmeldedaten, Port und `..`. `allowsTestServer`: zusätzlich `http://127.0.0.1` für die
    /// UI-Tests (nur Debug-Builds mit Test-Store).
    public static func isAllowed(_ url: URL, allowsTestServer: Bool = false) -> Bool {
        if allowsTestServer, url.scheme == "http", url.host() == "127.0.0.1", url.user() == nil { return true }
        guard url.scheme == "https", url.host()?.lowercased() == "github.com",
              url.user() == nil, url.password() == nil, url.port == nil
        else { return false }
        let components = url.pathComponents
        return components.count > releasePath.count
            && Array(components.prefix(releasePath.count)) == releasePath
            && !components.contains("..")
    }
}
