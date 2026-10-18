import XCTest

extension XCUIApplication {
    /// Quill für UI-Tests: ohne gespeicherten Fensterzustand und mit Daten nur im
    /// Arbeitsspeicher.
    ///
    /// Wurde das letzte Fenster geschlossen und die App danach hart beendet
    /// (z. B. Xcode-Stop nach ⌘R), stellt AppKit „0 Fenster“ wieder her. Starts
    /// über Finder/Dock öffnen trotzdem ein Fenster, programmatische Starts durch
    /// XCTest nicht. Siehe docs/decisions.md, ADR-008.
    ///
    /// `-QuillInMemoryStore YES` sorgt dafür, dass Tests nie die echte Datenbank
    /// oder die Backups des Nutzers berühren (`QuillPersistence.inMemoryArgument`).
    static func quill() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchArguments += ["-QuillInMemoryStore", "YES"]
        return app
    }
}
