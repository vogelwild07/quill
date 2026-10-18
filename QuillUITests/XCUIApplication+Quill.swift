import XCTest

extension XCUIApplication {
    /// Quill für UI-Tests: ohne gespeicherten Fensterzustand starten.
    ///
    /// Wurde das letzte Fenster geschlossen und die App danach hart beendet
    /// (z. B. Xcode-Stop nach ⌘R), stellt AppKit „0 Fenster“ wieder her. Starts
    /// über Finder/Dock öffnen trotzdem ein Fenster, programmatische Starts durch
    /// XCTest nicht. Siehe docs/decisions.md, ADR-008.
    static func quill() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        return app
    }
}
