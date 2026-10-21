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
    ///
    /// `-QuillWindowsOnMainScreen YES` legt jedes Fenster auf den Hauptbildschirm
    /// (`TestWindowScreen`), damit der Kontrast-Audit mit mehreren Monitoren gleich ausfällt.
    ///
    /// Mit `storeDirectory` liegt die Datenbank stattdessen in diesem Unterordner
    /// des temporären Ordners der App (`QuillPersistence.storeDirectoryArgument`),
    /// für Tests über Neustarts hinweg; auch dann nie die echten Daten.
    static func quill(storeDirectory: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchArguments += ["-QuillWindowsOnMainScreen", "YES"]
        if let storeDirectory {
            app.launchArguments += ["-QuillStoreDirectory", storeDirectory]
        } else {
            app.launchArguments += ["-QuillInMemoryStore", "YES"]
        }
        return app
    }
}

extension XCUIElement {
    /// Zeilen des Seitenbaums in der Sidebar, ohne Gruppen und Favoriten (ADR-017).
    var pageRows: XCUIElementQuery {
        outlineRows.containing(.textField, identifier: "sidebar.page")
    }

    /// Zeilen im Abschnitt „Favoriten“.
    var favoriteRows: XCUIElementQuery {
        outlineRows.containing(.textField, identifier: "sidebar.favorite")
    }
}
