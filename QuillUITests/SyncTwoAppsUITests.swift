import AppKit
import XCTest

/// Die Fälle aus `docs/synctest.md` mit zwei Geräten: Synctest A und B (eigene
/// Bundle-IDs, eigene Container, `Scripts/make-synctest.sh`) laufen nebeneinander
/// und teilen sich einen Wegwerf-Ordner im temporären Ordner dieses Test-Runners
/// (`-QuillSyncSharedFolder`, freigegeben nur in `App/QuillSynctest.entitlements`).
/// Stores nur im temporären Ordner der jeweiligen App (`-QuillStoreDirectory`), nie
/// die festen Stores der Varianten und nie der echte Store.
///
/// Läuft nur über `Scripts/test-synctest-ui.sh` (`TEST_RUNNER_QUILL_SYNC_UI=1`), sonst
/// übersprungen: Die Varianten müssen frisch gebaut sein. Per Hand bleiben Fall 13
/// (iCloud Drive) und „Neu beginnen …“ aus Fall 11 (Dateiauswahl), beide in Phase 13.
@MainActor
final class SyncTwoAppsUITests: XCTestCase {
    private var a: Device!
    private var b: Device!
    private var folders: [URL] = []
    private let run = UUID().uuidString

    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["QUILL_SYNC_UI"] == "1" else {
            throw XCTSkip("Nur über Scripts/test-synctest-ui.sh")
        }
        continueAfterFailure = false
        a = Device(name: "A", run: run)
        b = Device(name: "B", run: run)
    }

    override func tearDown() async throws {
        // Rot: A und B noch kurz laufen lassen, damit test-synctest-ui.sh Stack-Stichproben
        // nehmen kann (Wächter fragt jede Sekunde, `sample` braucht 3 s).
        if (testRun?.failureCount ?? 0) > 0 {
            try? await Task.sleep(for: .seconds(6))
        }
        a?.app.terminate()
        b?.app.terminate()
        a?.pasteboard.releaseGlobally()
        b?.pasteboard.releaseGlobally()
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
    }

    // MARK: - Fälle

    /// Fall 1 und 2: A schaltet ein, B mit eigenen Seiten fragt erst und führt dann zusammen.
    func testEnableAndSecondDevice() throws {
        let folder = try makeFolder("main")
        a.launch(folder: "main")
        a.createPage("A eins")
        a.enableSync()
        XCTAssertTrue(files(in: folder).contains { $0.hasPrefix("Quill/quill.json ") }, "Kein quill.json")
        a.assertBackupExists("Vor dem Einschalten des Sync")

        b.launch(folder: "main")
        b.createPage("B eins")
        b.createPage("B zwei")
        let before = files(in: folder, excludingDevices: true)
        b.enableSync(expectStatus: "Wartet auf deine Zustimmung")
        XCTAssertEqual(files(in: folder, excludingDevices: true), before, "Vor dem Zustimmen geschrieben")
        b.confirmMerge()
        converge()
        for device in [a!, b!] {
            device.assertTitles(["A eins", "B eins", "B zwei"], sorted: true)
        }
    }

    /// Fall 3: Unterseite, Favorit, Überschrift, Liste, abgehaktes To-do, Code, fetter
    /// Text, Link und ein Bild kommen gleich an (verglichen als Markdown der Seite).
    func testContents() throws {
        try connectBoth(image: "120x60")
        a.createPage("Inhalte", text: "# Überschrift\r- Punkt\r\r[] Aufgabe")
        a.app.typeKey(.return, modifierFlags: .command)
        a.app.typeText("\r\rText ")
        a.app.typeKey("b", modifierFlags: .command)
        a.app.typeText("fett")
        a.app.typeKey("b", modifierFlags: .command)
        a.app.typeText(" und ")
        a.app.typeKey("m", modifierFlags: [.command, .shift])
        a.app.typeText("code")
        a.app.typeKey("m", modifierFlags: [.command, .shift])
        a.app.typeText(" und Link")
        for _ in 0..<4 { a.app.typeKey(.leftArrow, modifierFlags: .shift) }
        a.app.typeKey("k", modifierFlags: .command)
        let link = a.app.descendants(matching: .any)["editor.link.field"]
        XCTAssertTrue(link.waitForExistence(timeout: 5), "Kein Link-Feld")
        a.app.typeText("https://example.com\r")
        XCTAssertTrue(link.waitForNonExistence(timeout: 5), "Link-Feld bleibt offen")
        a.app.typeKey(.rightArrow, modifierFlags: .command)
        a.app.typeText("\r")
        a.app.typeKey("v", modifierFlags: .command)
        a.waitForEditor { $0.contains("\u{FFFC}") }
        a.window.buttons["page.favorite"].click()
        a.createPage("Unterseite", subpage: true)
        a.select("Inhalte")
        let markdown = a.copiedMarkdown()
        for part in ["# Überschrift", "Punkt", "[x] Aufgabe", "**fett**", "`code`", "[Link](https://example.com)"] {
            XCTAssertTrue(markdown.contains(part), "„\(part)“ fehlt in \(markdown)")
        }

        converge()
        b.expand("Inhalte")
        b.assertTitles(["Inhalte", "Unterseite"])
        b.assertFavorites(["Inhalte"])
        b.select("Inhalte")
        b.waitForEditor { $0.contains("\u{FFFC}") }
        b.wait("B: Bild lädt noch") { !self.b.window.descendants(matching: .any)["editor.imageLoading"].exists }
        XCTAssertEqual(b.copiedMarkdown(), markdown)
    }

    /// Fall 4: beide pausiert, A tippt vorne, B hinten; nach dem Fortsetzen beides.
    func testTypingWhilePaused() throws {
        try connectBoth()
        let page = "Absatz"
        a.createPage(page, text: "Mitte")
        converge()
        b.select(page)
        b.waitForEditor { $0 == "Mitte\n" }
        a.setPaused(true)
        b.setPaused(true)
        a.select(page)
        a.caretToStart()
        a.app.typeText("AAA ")
        b.caretToEndOfFirstBlock()
        b.app.typeText(" BBB")
        a.setPaused(false)
        b.setPaused(false)
        converge()
        for device in [a!, b!] { device.waitForEditor(device.name) { $0 == "AAA Mitte BBB\n" } }
    }

    /// Fall 5: A löscht einen Absatz, B ändert genau diesen; er bleibt mit B's Änderung.
    func testDeleteVersusEdit() throws {
        try connectBoth()
        a.createPage("Liste", text: "eins\rzwei\rdrei")
        converge()
        b.select("Liste")
        b.waitForEditor { $0 == "eins\nzwei\ndrei\n" }
        a.setPaused(true)
        b.setPaused(true)
        a.select("Liste")
        a.caretToStart()
        a.app.typeKey(.downArrow, modifierFlags: [])
        a.app.typeKey(.rightArrow, modifierFlags: .command)
        for _ in 0..<5 { a.app.typeKey(.delete, modifierFlags: []) }
        a.waitForEditor { $0 == "eins\ndrei\n" }
        b.caretToStart()
        b.app.typeKey(.downArrow, modifierFlags: [])
        b.app.typeKey(.rightArrow, modifierFlags: .command)
        b.app.typeText(" von B")
        a.setPaused(false)
        b.setPaused(false)
        converge()
        for device in [a!, b!] {
            device.waitForEditor(device.name) { $0.contains("zwei von B\n") && $0.hasPrefix("eins") && $0.hasSuffix("drei\n") }
        }
        // Der behaltene Absatz trägt das Zeichen „wiederhergestellt“; A entfernt die
        // Markierung, B übernimmt das (11.6).
        for device in [a!, b!] { device.waitForMarkers("editor.marker.restored", count: 1) }
        a.app.activate()
        a.element("editor.marker.restored").click()
        let clear = a.app.popovers.buttons["restored.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "A: kein Popover zum Zeichen")
        clear.click()
        a.waitForMarkers("editor.marker.restored", count: 0)
        converge()
        b.waitForMarkers("editor.marker.restored", count: 0)
        b.waitForEditor { $0.contains("zwei von B\n") }
    }

    /// Fall 6: derselbe Titel unterschiedlich; beide zeigen danach denselben und melden
    /// „Zwei Werte für ein Feld“, mit Sprung zur Seite aus den Einstellungen. Pausiert
    /// wird nicht gewählt; danach wählt A die Fassung von B, beide übernehmen sie (11.6).
    func testTwoValuesForOneField() throws {
        try connectBoth()
        a.createPage("Titel")
        a.createPage("Anderes")
        converge()
        a.setPaused(true)
        b.setPaused(true)
        a.rename("Titel", to: "Titel A")
        b.rename("Titel", to: "Titel B")
        a.setPaused(false)
        b.setPaused(false)
        converge()
        let shown = a.titles().filter { $0 != "Anderes" }
        XCTAssertEqual(shown.count, 1)
        XCTAssertTrue(["Titel A", "Titel B"].contains(shown.first ?? ""), "\(shown)")
        let title = try XCTUnwrap(shown.first)
        b.assertTitles(a.titles(), sorted: true)
        for device in [a!, b!] { device.assertSettingsShow("Zwei Werte für ein Feld") }

        // Einstellungen › Sync: Klick auf die Seite springt dorthin.
        b.select("Anderes")
        b.jumpToConflict(on: title)

        // Pausiert: Die Fassungen stehen da, wählen geht nicht.
        b.setPaused(true)
        let paused = b.openConflicts(on: title)
        let pausedButtons = paused.buttons.matching(identifier: "conflict.choose")
        XCTAssertEqual(pausedButtons.count, 2)
        XCTAssertTrue(pausedButtons.allElementsBoundByIndex.allSatisfy { !$0.isEnabled }, "B: Wählen trotz Pause")
        XCTAssertTrue(paused.descendants(matching: .any)["conflict.paused"].exists, "B: kein Hinweis auf die Pause")
        b.closePopover()
        b.setPaused(false)

        // Jede Fassung nennt ihr Gerät; A wählt die von B.
        let popover = a.openConflicts(on: title)
        let buttons = popover.buttons.matching(identifier: "conflict.choose")
        XCTAssertEqual(Set(buttons.allElementsBoundByIndex.map(\.label)), ["Titel A von Gerät A wählen", "Titel B von Gerät B wählen"])
        buttons.matching(NSPredicate(format: "label == %@", "Titel B von Gerät B wählen")).firstMatch.click()
        a.closePopover()
        converge()
        for device in [a!, b!] {
            device.assertTitles(["Anderes", "Titel B"], sorted: true)
            device.select("Titel B")
            device.wait("\(device.name): Hinweis auf Konflikt bleibt") { !device.element("detail.conflicts").exists }
            device.assertSettingsLack("Zwei Werte für ein Feld")
        }
    }

    /// Fall 7: Papierkorb kommt an, Bearbeiten gewinnt gegen Papierkorb, Leeren nur je Gerät.
    func testTrash() throws {
        try connectBoth()
        a.createPage("Weg")
        a.createPage("Umstritten")
        converge()
        a.trash("Weg")
        converge()
        b.assertTitles(["Umstritten"])
        b.assertTrash(["Weg"])

        a.setPaused(true)
        b.setPaused(true)
        a.trash("Umstritten")
        b.select("Umstritten")
        b.caretToStart()
        b.app.typeText("bearbeitet")
        a.setPaused(false)
        b.setPaused(false)
        converge()
        for device in [a!, b!] { device.assertTitles(["Umstritten"]) }
        // Die behaltene Seite ist markiert: im Seitenkopf und im Kontextmenü der Sidebar.
        // A entfernt die Markierung, B übernimmt das (11.6).
        for device in [a!, b!] {
            device.select("Umstritten")
            device.wait("\(device.name): kein Hinweis „Hier behalten“") { device.element("detail.restored.clear").exists }
        }
        XCTAssertTrue(b.contextMenuHas("Markierung entfernen", on: "Umstritten"), "B: Kontextmenü ohne „Markierung entfernen“")
        a.element("detail.restored.clear").click()
        a.wait("A: Hinweis bleibt") { !self.a.element("detail.restored.clear").exists }
        converge()
        b.select("Umstritten")
        b.wait("B: Hinweis bleibt") { !self.b.element("detail.restored.clear").exists }
        XCTAssertFalse(b.contextMenuHas("Markierung entfernen", on: "Umstritten"), "B: Markierung noch im Kontextmenü")

        a.emptyTrash()
        converge()
        b.assertTrash(["Weg"])
        b.emptyTrash()
        converge()
        for device in [a!, b!] {
            device.assertTitles(["Umstritten"])
            device.assertTrash([])
        }
    }

    /// Fall 8: Pausiert schreibt A nichts, auch nach einem Neustart; danach kommt alles an.
    func testPauseWritesNothing() throws {
        let folder = try connectBoth()
        a.setPaused(true)
        let before = files(in: folder)
        a.createPage("Pausiert eins", text: "geschrieben")
        a.createPage("Pausiert zwei")
        a.quit()
        a.relaunch()
        a.openSettings()
        a.waitForStatus("Pausiert")
        a.closeSettings()
        XCTAssertEqual(files(in: folder), before, "Pausiert geschrieben")
        a.setPaused(false)
        converge()
        b.assertTitles(["Pausiert eins", "Pausiert zwei"], sorted: true)
    }

    /// Fall 9: Eine kaputte Datei von A meldet B als unlesbar, sonst läuft alles weiter.
    func testUnreadableFile() throws {
        let folder = try connectBoth()
        let device = try XCTUnwrap(a.deviceID, "Geräte-ID von A unbekannt")
        // Erst eine Seite, damit A einen eigenen Seitenbaum-Ordner hat.
        a.createPage("Vorher")
        converge()
        a.setPaused(true)
        a.createPage("Nach der Reparatur")
        let tree = folder.appending(path: "Quill/tree/\(device)", directoryHint: .isDirectory)
        let numbers = try FileManager.default.contentsOfDirectory(atPath: tree.path).compactMap { Int($0.prefix(12)) }
        let broken = tree.appending(path: String(format: "%012d.changes", (numbers.max() ?? 0) + 1))
        try Data("kaputt".utf8).write(to: broken)
        b.syncNow()
        // Den Pfad in der aufgeklappten Gruppe prüft der Handtest: XCUITest klappt die
        // Gruppe in den Einstellungen nicht auf (weder Klick noch Tastatur).
        b.assertSettingsShow("Unlesbare Dateien")
        try FileManager.default.removeItem(at: broken)
        a.setPaused(false)
        converge()
        b.assertTitles(["Nach der Reparatur", "Vorher"], sorted: true)
    }

    /// Fall 10: Ein fremder Quill-Ordner fragt erst; „Sync ausschalten“ lässt beide
    /// Ordner unverändert. Zurück zum bisherigen Ordner führt ohne Rückfrage zusammen.
    func testForeignFolder() throws {
        // Fremder Bestand: ein drittes Gerät (Variante A mit eigenem Store) befüllt den Ordner.
        let foreign = try makeFolder("foreign")
        let other = Device(name: "A", run: run, store: "fremd")
        other.launch(folder: "foreign")
        other.createPage("Fremd")
        other.enableSync()
        other.quit()
        let folder = try connectBoth()

        b.turnOffSync()
        b.quit()
        let mainBefore = files(in: folder, excludingDevices: true)
        let foreignBefore = files(in: foreign, excludingDevices: true)
        b.relaunch(folder: "foreign")
        b.enableSync(expectStatus: "Wartet auf deine Zustimmung")
        b.app.buttons["Sync ausschalten"].click()
        XCTAssertTrue(b.app.buttons["sync.enable"].waitForExistence(timeout: 5), "Sync nicht aus")
        b.closeSettings()
        XCTAssertEqual(files(in: folder, excludingDevices: true), mainBefore, "Bisheriger Ordner verändert")
        XCTAssertEqual(files(in: foreign, excludingDevices: true), foreignBefore, "Fremder Ordner verändert")

        b.quit()
        b.relaunch(folder: "main")
        b.enableSync()
        XCTAssertFalse(b.app.buttons["sync.confirmFolder"].exists, "Rückfrage beim bisherigen Ordner")
        XCTAssertFalse(b.titles().contains("Fremd"))
    }

    /// Fall 11, „Zusammenführen“: Backup einspielen schaltet den Sync aus; danach holt
    /// das Zusammenführen die neueren Stände aus dem Ordner zurück.
    func testRestoreAndMerge() throws {
        try connectBoth()
        a.createPage("Nach dem Backup")
        converge()
        a.restoreBackup("Vor dem Einschalten des Sync")
        a.relaunch()
        let notice = a.window.sheets.firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "Keine Meldung nach dem Start")
        notice.buttons["OK"].click()
        let merge = a.app.buttons["syncReconnect.merge"]
        XCTAssertTrue(merge.waitForExistence(timeout: 10), "Keine Rückfrage zum Sync")
        merge.click()
        XCTAssertTrue(merge.waitForNonExistence(timeout: 10))
        a.syncNow()
        a.assertTitles(["Nach dem Backup"])
    }

    /// Fall 12: B wird mitten im Abgleich beendet (Haltepunkt vor dem Schreiben der
    /// vierten Seite, `-QuillSyncHaltBeforePage`); nach dem Neustart ist alles einmal da.
    func testQuitDuringSync() throws {
        try connectBoth()
        b.quit()
        let pages = (1...8).map { "Seite \($0)" }
        for page in pages { a.createPage(page, text: "Text von \(page)") }
        a.syncNow()

        b.relaunch(extra: ["-QuillSyncHaltBeforePage", "4"])
        b.openSettings()
        let halted = b.app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR value == %@", "3 / 8", "3 / 8")).firstMatch
        XCTAssertTrue(halted.waitForExistence(timeout: 30), "Abgleich hält nicht bei 3 / 8")
        sleep(1)
        XCTAssertTrue(halted.exists, "Abgleich lief über den Haltepunkt hinaus")
        // Bedienbar, während der Abgleich steht.
        b.closeSettings()
        XCTAssertTrue(b.outline.waitForExistence(timeout: 5))
        b.quit()

        b.relaunch()
        converge()
        b.assertTitles(pages, sorted: true)
        for page in pages {
            b.select(page)
            b.waitForEditor(page) { $0 == "Text von \(page)\n" }
        }
    }

    /// Fall 14: A tippt ohne Pause am Ende des Absatzes, B schreibt vorne und gleicht
    /// ab. A übernimmt B's Text, während getippt wird; der Cursor bleibt hinter dem
    /// Getippten, nichts fehlt, kein Absatz doppelt. Mit der normalen Wartezeit vor dem
    /// Speichern (300 ms) lädt A dabei neu; das Zusammenführen ungespeicherter Eingaben
    /// prüft `testTypingWithoutPauseMergesUnsavedText`.
    func testTypingWithoutPause() throws {
        try connectBoth()
        try prepareNote()
        let words = ["eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf"]
        var shownWhileTyping = 0
        for (index, word) in words.enumerated() {
            a.app.typeText(" \(word)")
            if index == 2 {
                // B schreibt vorne und gleicht ab, während A weitertippt.
                b.select("Notiz")
                b.caretToStart()
                b.app.typeText("BBB ")
                b.syncNow()
                a.app.activate()
            } else if index > 2, a.editorText.hasPrefix("BBB ") {
                shownWhileTyping += 1
            }
            // Kurze Pausen wie beim Tippen; der Abgleich von A startet 2 s nach einer Änderung.
            RunLoop.current.run(until: .now.addingTimeInterval(0.7))
        }
        try assertBothEnd(with: "BBB Mitte" + words.map { " \($0)" }.joined())
        let summary = "„BBB “ in A sichtbar nach \(shownWhileTyping) von \(words.count - 3) Wörtern nach dem Abgleich von B"
        XCTContext.runActivity(named: summary) { _ in }
        print("SYNC14 \(summary)")
    }

    /// Fall 14 mit ungespeicherten Eingaben: A wartet 8 s vor dem Speichern
    /// (`-QuillSaveDelay`) und tippt, bevor und nachdem B abgleicht. Der Abgleich von A
    /// schreibt B's Text in den Store, während A's Text noch offen ist; beim Speichern
    /// führt die Bridge je Block zusammen (`BlockMerge`), statt zu überschreiben.
    func testTypingWithoutPauseMergesUnsavedText() throws {
        try connectBoth(saveDelayA: 8000)
        try prepareNote()
        a.app.typeText(" eins zwei")
        b.select("Notiz")
        b.caretToStart()
        b.app.typeText("BBB ")
        a.app.activate()
        a.app.typeText(" drei")
        b.syncNow()
        // Der Abgleich beim Aktivieren holt B's Text, A's Eingaben sind noch offen.
        a.app.activate()
        for word in ["vier", "fünf", "sechs"] {
            a.app.typeText(" \(word)")
            RunLoop.current.run(until: .now.addingTimeInterval(0.7))
        }
        try assertBothEnd(with: "BBB Mitte eins zwei drei vier fünf sechs", timeout: 30)
    }

    /// B legt „Notiz“ mit dem Absatz „Mitte“ an; A öffnet sie, Cursor ans Ende.
    private func prepareNote() throws {
        b.createPage("Notiz", text: "Mitte")
        converge()
        a.select("Notiz")
        a.waitForEditor { $0 == "Mitte\n" }
        a.caretToEndOfFirstBlock()
    }

    /// A zeigt `text` (ein Absatz), der Cursor steht dahinter; danach haben A und B
    /// denselben Absatz, nichts doppelt.
    private func assertBothEnd(with text: String, timeout: TimeInterval = 15) throws {
        a.waitForEditor("A übernimmt B", timeout: timeout) { $0 == text + "\n" }
        a.app.typeText(" Ende")
        a.waitForEditor("Cursor", timeout: timeout) { $0 == text + " Ende\n" }
        converge()
        for device in [a!, b!] {
            device.select("Notiz")
            device.waitForEditor(device.name, timeout: timeout) { $0 == text + " Ende\n" }
        }
    }

    // MARK: - Ablauf

    /// A und B mit gemeinsamem Ordner „main“, B hat zugestimmt, beide abgeglichen.
    @discardableResult
    private func connectBoth(image: String? = nil, saveDelayA: Int? = nil) throws -> URL {
        let folder = try makeFolder("main")
        a.launch(folder: "main", image: image, extra: saveDelayA.map { ["-QuillSaveDelay", "\($0)"] } ?? [])
        a.enableSync()
        a.deviceID = try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "Quill/devices").path)
            .first.map { String($0.dropLast(".json".count)) }
        b.launch(folder: "main", image: image)
        b.enableSync(expectStatus: "Wartet auf deine Zustimmung")
        b.confirmMerge()
        converge()
        return folder
    }

    /// Zwei Runden „Jetzt abgleichen“ in A und B: Danach hat jeder alles vom anderen.
    private func converge() {
        for _ in 0..<2 {
            a.syncNow()
            b.syncNow()
        }
    }

    private func makeFolder(_ name: String) throws -> URL {
        // Flach: `-QuillSyncSharedFolder` nimmt nur einen Namen, keinen Pfad.
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "QuillSyncUITests/\(run)-\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folders.append(folder)
        return folder
    }

    /// Dateien im Ordner mit Inhalt (als Prüfsumme), relativ zum Ordner.
    private func files(in folder: URL, excludingDevices: Bool = false) -> [String] {
        let paths = (FileManager.default.enumerator(atPath: folder.path)?.allObjects as? [String]) ?? []
        return paths.sorted().compactMap { path in
            if excludingDevices, path.hasPrefix("Quill/devices") { return nil }
            var isDirectory: ObjCBool = false
            let url = folder.appending(path: path)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return path }
            return "\(path) \((try? Data(contentsOf: url))?.hashValue ?? 0)"
        }
    }
}

/// Eine der beiden Testvarianten mit ihrem Test-Store.
@MainActor
private final class Device {
    let name: String
    let app: XCUIApplication
    let pasteboard: NSPasteboard
    private let store: String
    private let run: String
    private var folder = "main"
    private var image: String?
    var deviceID: String?

    init(name: String, run: String, store: String? = nil) {
        self.name = name
        self.run = run
        app = XCUIApplication(bundleIdentifier: "io.github.vogelwild07.quill.synctest.\(name.lowercased())")
        self.store = "uitest-sync-\(store ?? name)-\(run)"
        pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.vogelwild07.quill.uitests.\(name)-\(run)"))
    }

    // MARK: Start und Ende

    func launch(folder: String, image: String? = nil, extra: [String] = []) {
        self.folder = folder
        self.image = image
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES", "-QuillStoreDirectory", store,
            "-QuillSyncSharedFolder", "\(run)-\(folder)", "-QuillPasteboardName", pasteboard.name.rawValue,
            // Beide laufen auf demselben Mac; sonst hießen beide Geräte gleich (11.6).
            "-QuillSyncDeviceName", "Gerät \(name)",
        ] + XCUIApplication.languageArguments(language: "de", region: "DE") + (image.map { ["-QuillTestImage", $0] } ?? []) + extra
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 15), "\(name) ohne Fenster")
    }

    func relaunch(folder: String? = nil, extra: [String] = []) {
        launch(folder: folder ?? self.folder, image: image, extra: extra)
    }

    /// ⌘Q wie der Nutzer; offene Änderungen werden dabei gespeichert.
    func quit() {
        app.activate()
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 30), "\(name) beendet sich nicht")
    }

    // MARK: Fenster

    var window: XCUIElement {
        app.windows.matching(NSPredicate(format: "identifier BEGINSWITH %@", "main-")).firstMatch
    }

    var outline: XCUIElement { window.outlines["sidebar.pages"] }

    var editor: XCUIElement { window.textViews["editor.text"] }

    var editorText: String { editor.value as? String ?? "" }

    // MARK: Seiten

    func titles() -> [String] {
        outline.pageRows.allElementsBoundByIndex.map { $0.textFields.firstMatch.value as? String ?? "" }
    }

    /// ⌘N bzw. ⇧⌘N, Titel, optional ↩ und Text im ersten Absatz.
    func createPage(_ title: String, subpage: Bool = false, text: String? = nil) {
        app.activate()
        window.click()
        let count = outline.pageRows.count
        app.typeKey("n", modifierFlags: subpage ? [.command, .shift] : .command)
        wait("\(name): neue Seite") { self.outline.pageRows.count == count + 1 }
        let field = window.descendants(matching: .any)["detail.title"]
        wait("\(name): Fokus im Titel") { field.value(forKey: "hasKeyboardFocus") as? Bool == true }
        app.typeText(title)
        wait("\(name): Titel „\(title)“") { self.titles().contains(title) }
        if let text {
            app.typeText("\r")
            wait("\(name): Fokus im Editor") { self.editor.value(forKey: "hasKeyboardFocus") as? Bool == true }
            app.typeText(text)
        }
    }

    /// Klappt die Zeile auf (→ in der Sidebar), damit Unterseiten Zeilen sind.
    func expand(_ title: String) {
        select(title)
        outline.pageRows.containing(NSPredicate(format: "value == %@", title)).firstMatch.click()
        app.typeKey(.rightArrow, modifierFlags: [])
    }

    func select(_ title: String) {
        app.activate()
        let row = outline.pageRows.containing(NSPredicate(format: "value == %@", title)).firstMatch
        wait("\(name): Seite „\(title)“") { row.exists }
        row.click()
        wait("\(name): Fenster „\(title)“") { self.window.title == title }
    }

    func rename(_ title: String, to newTitle: String) {
        select(title)
        let field = window.descendants(matching: .any)["detail.title"]
        field.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText(newTitle)
        app.typeText("\r")
        wait("\(name): Titel „\(newTitle)“") { self.titles().contains(newTitle) }
    }

    func trash(_ title: String) {
        select(title)
        outline.pageRows.containing(NSPredicate(format: "value == %@", title)).firstMatch.click()
        app.typeKey(.delete, modifierFlags: .command)
        wait("\(name): „\(title)“ im Papierkorb") { !self.titles().contains(title) }
    }

    func emptyTrash() {
        app.activate()
        window.buttons["sidebar.trash"].click()
        window.buttons["trash.empty"].click()
        let sheet = window.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "\(name): keine Rückfrage beim Leeren")
        sheet.buttons["action-button-1"].click()
        wait("\(name): Papierkorb leer") { self.trashRows().isEmpty }
    }

    private func trashRows() -> [String] {
        window.descendants(matching: .any).matching(identifier: "trash.row").allElementsBoundByIndex.map { row in
            [(row.value as? String) ?? "", row.label].joined(separator: " ")
        }
    }

    func assertTrash(_ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        app.activate()
        window.buttons["sidebar.trash"].click()
        wait("\(name): Papierkorb \(expected) statt \(trashRows())", file: file, line: line) {
            let rows = self.trashRows()
            return rows.count == expected.count && expected.allSatisfy { title in rows.contains { $0.contains(title) } }
        }
        app.typeKey(.escape, modifierFlags: [])
    }

    func assertTitles(_ expected: [String], sorted: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        app.activate()
        wait("\(name): Sidebar \(titles()) statt \(expected)", timeout: 15, file: file, line: line) {
            sorted ? self.titles().sorted() == expected.sorted() : self.titles() == expected
        }
    }

    func assertFavorites(_ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        let rows = outline.outlineRows.containing(.textField, identifier: "sidebar.favorite")
        wait("\(name): Favoriten", file: file, line: line) {
            rows.allElementsBoundByIndex.map { $0.textFields.firstMatch.value as? String ?? "" } == expected
        }
    }

    // MARK: Editor

    func waitForEditor(
        _ what: String = "", timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line,
        _ matches: @escaping (String) -> Bool
    ) {
        wait("\(name) \(what): Editor \(editorText.debugDescription)", timeout: timeout, file: file, line: line) { matches(self.editorText) }
    }

    func caretToStart() {
        app.activate()
        editor.click()
        app.typeKey(.upArrow, modifierFlags: .command)
    }

    func caretToEndOfFirstBlock() {
        caretToStart()
        app.typeKey(.rightArrow, modifierFlags: .command)
    }

    /// ⌘A, ⌘C im Editor; Markdown aus der eigenen Zwischenablage.
    func copiedMarkdown() -> String {
        editor.click()
        app.typeKey("a", modifierFlags: .command)
        let before = pasteboard.changeCount
        app.typeKey("c", modifierFlags: .command)
        wait("\(name): kopiert") { self.pasteboard.changeCount != before }
        app.typeKey(.upArrow, modifierFlags: .command)
        return pasteboard.string(forType: NSPasteboard.PasteboardType("net.daringfireball.markdown")) ?? ""
    }

    // MARK: Sync

    func openSettings() {
        app.activate()
        app.typeKey(",", modifierFlags: .command)
        let tab = app.toolbars.buttons["Sync"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(name): kein Bereich „Sync“")
        tab.click()
    }

    /// ⌘W, nur wenn die Einstellungen offen sind (sonst schlösse es das Fenster).
    func closeSettings() {
        app.activate()
        if app.toolbars.buttons["Sync"].exists { app.typeKey("w", modifierFlags: .command) }
        wait("\(name): Einstellungen bleiben offen") { !self.app.toolbars.buttons["Sync"].exists }
    }

    func enableSync(expectStatus status: String = "Abgeglichen") {
        openSettings()
        let enable = app.buttons["sync.enable"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5), "\(name): Sync nicht aus")
        enable.click()
        waitForStatus(status)
        if status == "Abgeglichen" { closeSettings() }
    }

    func confirmMerge() {
        let confirm = app.buttons["sync.confirmFolder"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "\(name): keine Rückfrage")
        confirm.click()
        waitForStatus("Abgeglichen")
        closeSettings()
    }

    func turnOffSync() {
        openSettings()
        app.buttons["sync.turnOff"].click()
        let confirm = app.buttons["sync.turnOff.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(app.buttons["sync.enable"].waitForExistence(timeout: 5), "\(name): Sync nicht aus")
        closeSettings()
    }

    func setPaused(_ paused: Bool) {
        openSettings()
        let toggle = app.descendants(matching: .any)["sync.pause"]
        if statusText.contains("Pausiert") != paused { toggle.click() }
        waitForStatus(paused ? "Pausiert" : "Abgeglichen")
        closeSettings()
    }

    /// „Jetzt abgleichen“ und warten, bis der Abgleich fertig ist.
    func syncNow() {
        openSettings()
        let now = app.buttons["sync.now"]
        wait("\(name): „Jetzt abgleichen“ bereit") { now.exists && now.isEnabled }
        now.click()
        waitForStatus("Abgeglichen")
        wait("\(name): Abgleich fertig") { now.isEnabled }
        closeSettings()
    }

    func waitForStatus(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        wait("\(name): Status „\(statusText)“ statt „\(text)“", timeout: 20, file: file, line: line) {
            self.statusText.contains(text)
        }
    }

    private var statusText: String {
        let status = app.descendants(matching: .any)["sync.status"]
        guard status.exists else { return "fehlt" }
        let texts = status.descendants(matching: .staticText).allElementsBoundByIndex.map { $0.value as? String ?? $0.label }
        return ([status.label, status.value as? String ?? ""] + texts).joined(separator: " ")
    }

    /// Text in den Einstellungen › Sync.
    func assertSettingsShow(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        openSettings()
        let match = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)).firstMatch
        wait("\(name): „\(text)“ in den Einstellungen", file: file, line: line) { match.exists }
        closeSettings()
    }

    /// Text fehlt in den Einstellungen › Sync.
    func assertSettingsLack(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        openSettings()
        let match = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)).firstMatch
        wait("\(name): „\(text)“ noch in den Einstellungen", file: file, line: line) { !match.exists }
        closeSettings()
    }

    // MARK: Konflikte und Markierungen (11.6)

    func element(_ identifier: String) -> XCUIElement {
        window.descendants(matching: .any)[identifier]
    }

    /// Klick auf die Seite unter „Zwei Werte für ein Feld“ in den Einstellungen springt
    /// im Fenster dorthin. Danach ist das Hauptfenster vorn; ⌘W allein träfe es.
    func jumpToConflict(on title: String) {
        openSettings()
        let link = app.descendants(matching: .any).matching(identifier: "sync.conflictPage").firstMatch
        // Knöpfe im Stil `.link` meldet SwiftUI nicht als Knopf.
        XCTAssertTrue(link.waitForExistence(timeout: 5), "\(name): keine Seite mit Konflikt in den Einstellungen")
        link.click()
        wait("\(name): Sprung zu „\(title)“, Fenster zeigt „\(window.title)“") { self.window.title == title }
        // ⌘, holt die Einstellungen wieder nach vorn, dann trifft ⌘W sie.
        openSettings()
        closeSettings()
        wait("\(name): Fenster zeigt nach dem Schließen „\(window.title)“") { self.window.title == title }
    }

    /// „Wählen …“ im Seitenkopf; gibt das Popover zurück.
    func openConflicts(on title: String) -> XCUIElement {
        select(title)
        let button = element("detail.conflicts")
        wait("\(name): kein Hinweis auf Konflikt") { button.exists }
        button.click()
        let list = app.descendants(matching: .any)["conflict.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5), "\(name): kein Popover mit Fassungen")
        return list
    }

    func closePopover() {
        app.typeKey(.escape, modifierFlags: [])
        wait("\(name): Popover bleibt offen") { !self.app.descendants(matching: .any)["conflict.list"].exists }
    }

    func waitForMarkers(_ identifier: String, count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let markers = editor.descendants(matching: .any).matching(identifier: identifier)
        wait("\(name): \(markers.count) statt \(count) Zeichen „\(identifier)“", timeout: 15, file: file, line: line) {
            markers.count == count
        }
    }

    /// Rechtsklick auf die Zeile; `true`, wenn das Menü den Eintrag hat. Escape schließt es.
    func contextMenuHas(_ item: String, on title: String) -> Bool {
        app.activate()
        outline.pageRows.containing(NSPredicate(format: "value == %@", title)).firstMatch.rightClick()
        let entry = outline.menuItems[item]
        let menu = outline.menus.firstMatch
        _ = menu.waitForExistence(timeout: 5)
        let found = entry.exists
        app.typeKey(.escape, modifierFlags: [])
        return found
    }

    // MARK: Backup

    func assertBackupExists(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let sheet = openRestoreSheet()
        let row = backupRow(title, in: sheet)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(name): kein Backup „\(title)“", file: file, line: line)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
    }

    /// Wählt das Backup und bestätigt; die App beendet sich danach.
    func restoreBackup(_ title: String) {
        let sheet = openRestoreSheet()
        let row = backupRow(title, in: sheet)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(name): kein Backup „\(title)“")
        row.click()
        sheet.buttons["restore.confirm"].click()
        let note = app.staticTexts.containing(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Der Sync wird dafür ausgeschaltet", "Der Sync wird dafür ausgeschaltet")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "\(name): Bestätigung nennt den Sync nicht")
        window.descendants(matching: .button).matching(identifier: "Wiederherstellen und beenden").firstMatch.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 30), "\(name) beendet sich nicht")
    }

    private func openRestoreSheet() -> XCUIElement {
        app.activate()
        window.click()
        app.menuBars.menuBarItems["Ablage"].click()
        app.menuBars.menuItems["Backup wiederherstellen …"].click()
        let sheet = window.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "\(name): keine Backup-Liste")
        return sheet
    }

    private func backupRow(_ title: String, in sheet: XCUIElement) -> XCUIElement {
        sheet.descendants(matching: .any).matching(identifier: "restore.row")
            .containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", title, title)).firstMatch
    }

    // MARK: Warten

    func wait(
        _ message: @autoclosure () -> String, timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line, _ condition: @escaping () -> Bool
    ) {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition() {
            guard Date.now < deadline else {
                XCTFail(message(), file: file, line: line)
                return
            }
            RunLoop.current.run(until: .now.addingTimeInterval(0.2))
        }
    }
}
