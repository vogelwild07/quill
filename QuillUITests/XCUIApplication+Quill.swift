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

    /// Öffnet die Zeitreise der ersten Seite (⌥⌘Y) und gibt das Fenster zurück, sobald
    /// es die drei Tage aus `-QuillSeedTimeTravel` zeigt (12.3).
    @MainActor
    func openSeededTimeTravel(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let row = windows.firstMatch.outlines["sidebar.pages"].pageRows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Testseite fehlt", file: file, line: line)
        row.click()
        typeKey("y", modifierFlags: [.command, .option])
        let window = windows["Zeitreise: Zeitreise-Test"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Fenster „Zeitreise“ fehlt", file: file, line: line)
        XCTAssertTrue(window.timeTravelDays.element(boundBy: 2).waitForExistence(timeout: 10), "Drei Tage erwartet", file: file, line: line)
        return window
    }
}

extension XCUIElement {
    /// Zeilen des Seitenbaums in der Sidebar, ohne Gruppen und Favoriten (ADR-017).
    var pageRows: XCUIElementQuery {
        outlineRows.containing(.textField, identifier: "sidebar.page")
    }

    /// Tage im Fenster „Zeitreise“, neuester zuerst.
    var timeTravelDays: XCUIElementQuery {
        descendants(matching: .any).matching(identifier: "timeTravel.day")
    }

    /// Zeilen im Abschnitt „Favoriten“.
    var favoriteRows: XCUIElementQuery {
        outlineRows.containing(.textField, identifier: "sidebar.favorite")
    }
}
