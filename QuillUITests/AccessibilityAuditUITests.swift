import AppKit
import XCTest

/// Bedienungshilfen pro Ansicht: `performAccessibilityAudit` mit allen Prüfarten.
///
/// Jede Meldung lässt den Test fehlschlagen, außer den einzeln begründeten
/// Ausnahmen in `exception(for:in:)`. Keine Prüfart wird pauschal übergangen
/// (Phase 7.3, Befunde A1–A13). Was der Audit nicht sieht, prüft
/// `AccessibilityUITests` gezielt (z. B. eine nicht ausgewählte Papierkorb-Zeile).
@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    private var app: XCUIApplication!
    private let storeDirectory = "uitest-audit-\(UUID().uuidString)"
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.vogelwild07.quill.uitests.\(UUID().uuidString)"))

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication.quill(storeDirectory: storeDirectory)
        // Testbild erzeugt die App selbst in ihrer Zwischenablage (siehe `ImageBlockUITests`).
        app.launchArguments += ["-QuillPasteboardName", pasteboard.name.rawValue, "-QuillTestImage", "120x60"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.windows.firstMatch.click()
    }

    override func tearDown() async throws {
        app.terminate()
        pasteboard.releaseGlobally()
    }

    func testAuditAllViews() throws {
        audit("Fenster ohne Seite")

        createPage("Leer")
        audit("Leere Seite (Titel fokussiert)", orphans: .focusedTextField)
        app.typeText("\r")
        audit("Leere Seite (Editor fokussiert)")

        createPage("Inhalt")
        app.typeText("\r")
        app.typeText("# Überschrift\rText mit Inhalt\r[] Aufgabe\r\r> Zitat\r\r")
        app.typeKey("v", modifierFlags: .command)
        window.buttons["page.favorite"].click()
        audit("Seite mit Inhalt, Favorit")

        app.typeText("/")
        audit("Slash-Menü")
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("o", modifierFlags: .command)
        audit("Schnell öffnen (leer)", orphans: .quickOpen)
        app.typeText("Inh")
        audit("Schnell öffnen (Treffer)", orphans: .quickOpen)
        app.typeText("xyzq")
        audit("Schnell öffnen (keine Treffer)", orphans: .quickOpen)
        app.typeKey(.escape, modifierFlags: [])

        window.descendants(matching: .any)["sidebar.trash"].click()
        audit("Papierkorb (leer)")
        window.outlines["sidebar.pages"].pageRows.element(boundBy: 0).click()
        app.typeKey(.delete, modifierFlags: .command)
        window.descendants(matching: .any)["sidebar.trash"].click()
        audit("Papierkorb (ein Eintrag)")

        app.menuBars.menuBarItems["Ablage"].click()
        app.menuBars.menuItems["Backup wiederherstellen …"].click()
        XCTAssertTrue(window.sheets.firstMatch.waitForExistence(timeout: 5))
        audit("Backup wiederherstellen")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Festes dunkles Theme bei hellem oder dunklem System, danach die Einstellungen
    /// (ADR-024). Startargument wirkt nur mit Test-Store.
    func testAuditFixedThemeAndSettings() throws {
        app.terminate()
        app = XCUIApplication.quill(storeDirectory: storeDirectory)
        app.launchArguments += [
            "-QuillPasteboardName", pasteboard.name.rawValue, "-QuillEditorTheme", "lagune",
            "-QuillSyncTestFolder", "uitest-audit-sync-\(UUID().uuidString)",
            // Mit Erklärung: mehr Elemente im Reiter „KI“ als mit bereitem Modell.
            "-QuillFakeAI", "appleIntelligenceNotEnabled",
        ]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.windows.firstMatch.click()

        createPage("Lagune")
        app.typeText("\r")
        app.typeText("# Überschrift\rText mit Inhalt\r[] Aufgabe\r\r> Zitat\r\r")
        audit("Seite im festen Theme Lagune")

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["settings.preview"].waitForExistence(timeout: 5))
        audit("Einstellungen › Darstellung")
        app.descendants(matching: .any)["settings.theme.sonne"].click()
        audit("Einstellungen › Darstellung, Sonne gewählt")

        app.toolbars.buttons["Sync"].click()
        XCTAssertTrue(app.buttons["sync.enable"].waitForExistence(timeout: 5))
        audit("Einstellungen › Sync (aus)")
        app.buttons["sync.enable"].click()
        XCTAssertTrue(app.descendants(matching: .any)["sync.pause"].waitForExistence(timeout: 10))
        audit("Einstellungen › Sync (an)")
        app.toolbars.buttons["Zeitreise"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.imageRetention"].waitForExistence(timeout: 5))
        audit("Einstellungen › Zeitreise")
        app.toolbars.buttons["KI"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.aiUnavailable"].waitForExistence(timeout: 5))
        audit("Einstellungen › KI")
        app.toolbars.buttons["Spotlight"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.spotlight"].waitForExistence(timeout: 5))
        audit("Einstellungen › Spotlight")
        app.toolbars.buttons["Schnellnotiz"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.quickNote"].waitForExistence(timeout: 5))
        audit("Einstellungen › Schnellnotiz")
        app.toolbars.buttons["Lizenzen"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.licenses"].waitForExistence(timeout: 5))
        audit("Einstellungen › Lizenzen")
        app.typeKey("w", modifierFlags: .command)
    }

    /// Glas von Quill (ADR-036) in Stellung klar und getönt: Sidebar, Toolbar, Slash-Menü,
    /// Schnell öffnen und der Regler in den Einstellungen. Der Kontrast-Check misst das
    /// echte Glas über dem Schreibtisch dieses Macs.
    func testAuditGlass() throws {
        for (level, name) in [("0", "klar"), ("1", "getönt")] {
            app.terminate()
            app = XCUIApplication.quill(storeDirectory: storeDirectory)
            app.launchArguments += ["-QuillPasteboardName", pasteboard.name.rawValue, "-QuillTestGlass", level]
            app.launch()
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
            app.windows.firstMatch.click()

            createPage("Glas \(name)")
            app.typeText("\r")
            app.typeText("Text auf der Seite\r")
            window.buttons["page.favorite"].click()
            audit("Glas \(name): Sidebar und Toolbar")
            app.typeText("/")
            audit("Glas \(name): Slash-Menü")
            app.typeKey(.escape, modifierFlags: [])
            app.typeKey("o", modifierFlags: .command)
            audit("Glas \(name): Schnell öffnen", orphans: .quickOpen)
            app.typeKey(.escape, modifierFlags: [])

            app.typeKey(",", modifierFlags: .command)
            XCTAssertTrue(app.sliders["settings.glass.slider"].waitForExistence(timeout: 5))
            audit("Glas \(name): Einstellungen › Darstellung mit Regler")
            app.typeKey("w", modifierFlags: .command)
        }

        app.terminate()
        app = XCUIApplication.quill(storeDirectory: storeDirectory)
        app.launchArguments += ["-QuillTestGlass", "0.5", "-QuillTestReduceTransparency", "YES"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.windows.firstMatch.click()
        // Mit Seite: Sonst misst der Kontrast-Check den Leerzustand im Detail durch das
        // Einstellungsfenster hindurch, das davor liegt.
        createPage("Glas deckend")
        app.typeText("\r")
        audit("Glas deckend: Sidebar und Toolbar")
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["settings.glass.reduceTransparency"].waitForExistence(timeout: 5))
        audit("Einstellungen › Darstellung, „Transparenz reduzieren“")
        app.typeKey("w", modifierFlags: .command)
    }

    /// Rückfrage nach einem eingespielten Backup bei eingeschaltetem Sync (ADR-029).
    func testAuditSyncReconnect() throws {
        app.terminate()
        app = XCUIApplication.quill(storeDirectory: storeDirectory)
        app.launchArguments += ["-QuillSyncTestFolder", "uitest-audit-sync-\(UUID().uuidString)"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.typeKey(",", modifierFlags: .command)
        app.toolbars.buttons["Sync"].click()
        app.buttons["sync.enable"].click()
        XCTAssertTrue(app.descendants(matching: .any)["sync.pause"].waitForExistence(timeout: 10))
        app.typeKey("w", modifierFlags: .command)

        window.click()
        app.menuBars.menuBarItems["Ablage"].click()
        app.menuBars.menuItems["Backup wiederherstellen …"].click()
        let row = window.sheets.firstMatch.descendants(matching: .any).matching(identifier: "restore.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        window.sheets.firstMatch.buttons["restore.confirm"].click()
        let confirm = window.descendants(matching: .button).matching(identifier: "Wiederherstellen und beenden").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 30))

        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let notice = window.sheets.firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        notice.buttons["OK"].click()
        XCTAssertTrue(app.buttons["syncReconnect.later"].waitForExistence(timeout: 10))
        audit("Rückfrage zum Sync nach dem Backup")
        // Escape heißt „Später“: Der Sync bleibt aus, die Rückfrage geht zu.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["syncReconnect.later"].waitForNonExistence(timeout: 5))
    }

    /// Fenster „Zeitreise“ mit drei Tagen, früherer Stand gewählt (12.3, ADR-031).
    func testAuditTimeTravel() throws {
        app.terminate()
        app = XCUIApplication.quill(storeDirectory: storeDirectory)
        app.launchArguments += ["-QuillSeedTimeTravel", "YES"]
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let travel = app.openSeededTimeTravel()
        // Zeiger weg von der Zeile in der Sidebar: Deren Tooltip (Hilfetext des Systems,
        // ohne Beschreibung) erschien sonst im Audit, auch auf `main`.
        travel.timeTravelDays.element(boundBy: 0).hover()
        audit("Zeitreise (heute)")
        travel.timeTravelDays.element(boundBy: 2).click()
        audit("Zeitreise (früherer Tag)")
    }

    /// Blätter der lokalen KI (16.2–16.5, ADR-032) mit Ergebnis und mit Hinweis, Test-Modell
    /// statt Apple Intelligence.
    func testAuditSummary() throws {
        app.terminate()
        app = XCUIApplication.quill(storeDirectory: storeDirectory)
        app.launchArguments += ["-QuillPasteboardName", pasteboard.name.rawValue, "-QuillFakeAI", "available"]
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.click()
        app.typeKey("n", modifierFlags: .command)
        let title = window.descendants(matching: .any)["detail.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.typeText("Ausflug\rWir fahren an den See.")
        summarize()
        XCTAssertTrue(app.descendants(matching: .any)["summary.text"].waitForExistence(timeout: 10))
        audit("Zusammenfassung")
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("n", modifierFlags: .command)
        summarize()
        XCTAssertTrue(app.descendants(matching: .any)["summary.problem"].waitForExistence(timeout: 10))
        audit("Zusammenfassung (leere Seite)")
        app.typeKey(.escape, modifierFlags: [])

        // To-dos (16.3): Liste der Vorschläge.
        app.windows.firstMatch.textViews["editor.text"].click()
        app.typeText("Milch kaufen")
        app.typeKey("a", modifierFlags: .command)
        app.menuBars.menuBarItems["Seite"].click()
        app.menuBars.menuItems["To-dos vorschlagen …"].click()
        XCTAssertTrue(app.descendants(matching: .any)["todos.list"].waitForExistence(timeout: 10))
        audit("To-dos vorschlagen")
        // Eingefügt findet „Verwandte Seiten“ unten diese Seite.
        app.buttons["todos.insert"].click()

        // Frag deine Notizen (16.4): Antwort mit Quelle, dann ohne passende Seite.
        app.menuBars.menuBarItems["Ablage"].click()
        app.menuBars.menuItems["Frag deine Notizen …"].click()
        let question = app.descendants(matching: .any)["ask.question"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        app.typeText("Wohin fahren wir?\r")
        XCTAssertTrue(app.descendants(matching: .any)["ask.answer"].waitForExistence(timeout: 10))
        audit("Frag deine Notizen", orphans: .focusedTextField)
        question.doubleClick()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Xylophon?\r")
        XCTAssertTrue(app.descendants(matching: .any)["ask.problem"].waitForExistence(timeout: 10))
        audit("Frag deine Notizen (ohne Quelle)", orphans: .focusedTextField)
        app.typeKey(.escape, modifierFlags: [])

        // Verwandte Seiten (16.5): mit Treffer, dann ohne.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.typeText("Einkauf\rMilch kaufen")
        relatedPages()
        XCTAssertTrue(app.descendants(matching: .any)["related.terms"].waitForExistence(timeout: 10))
        audit("Verwandte Seiten")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.typeText("Kuchen")
        relatedPages()
        XCTAssertTrue(app.descendants(matching: .any)["related.emptyState.title"].waitForExistence(timeout: 10))
        audit("Verwandte Seiten (keine)")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Erinnerung an ein To-do (15.4): Blatt, dann Popover zum Zeichen.
    func testAuditReminder() throws {
        createPage("Auto")
        app.typeText("\r[] Reifen wechseln")
        app.menuBars.menuBarItems["Format"].click()
        app.menuBars.menuItems["Erinnerung …"].click()
        XCTAssertTrue(app.descendants(matching: .any)["reminder.date"].waitForExistence(timeout: 5))
        audit("Erinnerung")
        app.buttons["reminder.schedule"].click()
        let marker = window.descendants(matching: .any)["editor.marker.reminder"]
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        marker.click()
        XCTAssertTrue(app.buttons["reminder.marker.remove"].waitForExistence(timeout: 5))
        audit("Erinnerung (Zeichen)")
        app.typeKey(.escape, modifierFlags: [])
    }

    private func relatedPages() {
        app.menuBars.menuBarItems["Seite"].click()
        app.menuBars.menuItems["Verwandte Seiten …"].click()
    }

    private func summarize() {
        app.menuBars.menuBarItems["Seite"].click()
        app.menuBars.menuItems["Zusammenfassen …"].click()
    }

    // MARK: - Audit

    private var window: XCUIElement { app.windows.firstMatch }

    /// Was die Ausnahmen über die Ansicht wissen müssen; einmal vor dem Audit erhoben.
    private struct ViewState {
        /// Hüllen von SwiftUI: Fenster, Spalten des `NavigationSplitView`, Sheet.
        var layoutGroupFrames: [CGRect]
        /// Hosting-View im Seitenkopf (unter der beschrifteten Gruppe „Seitenkopf“).
        var headerContentFrame: CGRect?
        var toolbarFrames: [CGRect]
        /// Titelleiste je Fenster: vom oberen Rand bis zur Symbolleiste.
        var titlebarFrames: [CGRect]
        /// „Emojis & Symbole“ in der Touch Bar.
        var touchBarEmojiFrame: CGRect?
        /// Elemente im Sheet; alle anderen liegen dahinter.
        var sheetElementFrames: [CGRect]?
    }

    /// Über alle Fenster: Mit offenen Einstellungen liegt das Hauptfenster dahinter
    /// und wird mitgeprüft.
    private func viewState() -> ViewState {
        func frames(_ query: XCUIElementQuery) -> [CGRect] { query.allElementsBoundByIndex.map(\.frame) }
        let windows = app.windows.allElementsBoundByIndex
        let sheet = window.sheets.firstMatch
        let header = app.textViews["editor.text"].groups["Seitenkopf"].children(matching: .group).firstMatch
        let emoji = app.touchBars.firstMatch.popUpButtons["Emojis & Symbole"]
        return ViewState(
            layoutGroupFrames: windows.flatMap { window in
                frames(window.children(matching: .group)) + frames(window.splitGroups.firstMatch.children(matching: .group))
            } + (sheet.exists ? frames(sheet.children(matching: .group)) : []),
            headerContentFrame: header.exists ? header.frame : nil,
            toolbarFrames: frames(app.toolbars),
            titlebarFrames: windows.compactMap { window in
                let frame = window.frame
                guard let toolbar = frames(window.toolbars).first(where: { frame.contains($0) }) else { return nil }
                return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: toolbar.minY - frame.minY)
            },
            touchBarEmojiFrame: emoji.exists ? emoji.frame : nil,
            sheetElementFrames: sheet.exists ? [sheet.frame] + frames(sheet.descendants(matching: .any)) : nil
        )
    }

    /// Meldungen ohne Element lassen sich keiner Ursache zuordnen. Sie werden deshalb
    /// je Ansicht und Prüfart genau erwartet; eine mehr oder weniger ist ein Fehler.
    private struct Orphans {
        var parentChild = 0

        /// Feld-Editor von AppKit eines fokussierten SwiftUI-Textfelds (A6).
        static let focusedTextField = Orphans(parentChild: 1)
        /// Zusätzlich `.isModal` an „Schnell öffnen“, damit VoiceOver im Panel bleibt
        /// (A6, Entscheidung Nutzer).
        static let quickOpen = Orphans(parentChild: 2)

        func expected(_ type: XCUIAccessibilityAuditType) -> Int {
            type == .parentChild ? parentChild : 0
        }
    }

    private func audit(_ view: String, orphans: Orphans = Orphans()) {
        waitUntilSettled(view)
        let state = viewState()
        var unexpected: [String] = []
        var orphanCounts: [UInt64: (type: XCUIAccessibilityAuditType, count: Int)] = [:]
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                if issue.element == nil {
                    orphanCounts[issue.auditType.rawValue, default: (issue.auditType, 0)].count += 1
                } else if self.exception(for: issue, in: state) == nil {
                    unexpected.append(Self.describe(issue))
                }
                return true
            }
        } catch {
            XCTFail("\(view): Audit nicht ausgeführt: \(error)")
        }
        for issue in unexpected {
            XCTFail("\(view): \(issue)")
        }
        for (type, count) in orphanCounts.values where count != orphans.expected(type) {
            XCTFail("\(view): \(count) Meldungen ohne Element [\(type.rawValue)], erwartet \(orphans.expected(type))")
        }
        if orphanCounts[XCUIAccessibilityAuditType.parentChild.rawValue] == nil, orphans.parentChild > 0 {
            XCTFail("\(view): 0 Meldungen ohne Element [parentChild], erwartet \(orphans.parentChild)")
        }
    }

    /// Wartet, bis sich der Baum der Bedienungshilfen nicht mehr ändert (Animationen
    /// und Einblenden vorbei), statt eine feste Zeit zu schlafen. Verglichen werden
    /// Art, Kennung, Beschriftung und Rahmen, nicht Werte: Relative Daten im
    /// Papierkorb („vor 1 Sekunde“) laufen weiter.
    private func waitUntilSettled(_ view: String) {
        // Alle Fenster: Wechselt ein Bereich der Einstellungen, ändert deren Fenster
        // animiert die Größe, und die Rahmen von vorher stimmen nicht mehr.
        let app = app!
        var previous: [String]?
        let settled = NSPredicate { _, _ in
            guard let snapshot = try? app.snapshot() else { return false }
            let current = Self.layout(of: snapshot)
            defer { previous = current }
            return current == previous
        }
        let result = XCTWaiter().wait(for: [expectation(for: settled, evaluatedWith: nil)], timeout: 10)
        XCTAssertEqual(result, .completed, "\(view): Ansicht kommt nicht zur Ruhe")
    }

    /// Einzelne Ausnahmen, je mit Begründung. Alles andere ist ein Fehler.
    private func exception(for issue: XCUIAccessibilityAuditIssue, in state: ViewState) -> String? {
        let element = issue.element
        let type = element?.elementType
        let frame = element?.frame ?? .null
        let label = element?.label ?? ""
        let identifier = element?.identifier ?? ""

        switch issue.auditType {
        case .sufficientElementDescription:
            if type == .touchBar {
                return "Touch Bar des Systems für Textfelder, kein Inhalt von Quill (A12)."
            }
            if type == .group, label.isEmpty, state.layoutGroupFrames.contains(frame) {
                return "Hülle von SwiftUI (Fenster, Spalte, Sheet); ein Label erzeugt nur eine weitere Gruppe (A8)."
            }
            if type == .group, label.isEmpty, frame == state.headerContentFrame {
                return "Hosting-View im Seitenkopf; der Kopf selbst ist die beschriftete Gruppe „Seitenkopf“ (A3, A8)."
            }
            if type == .popUpButton, frame == state.touchBarEmojiFrame {
                return "Schaltfläche „Emojis & Symbole“ der Touch Bar, vom System (A12)."
            }
        case .action:
            if type == .popUpButton, frame == state.touchBarEmojiFrame {
                return "Schaltfläche „Emojis & Symbole“ der Touch Bar, vom System (A12)."
            }
        case .contrast:
            if identifier == "sidebar.group" {
                return "Gruppenköpfe im Systemstil der Source-List (A10, Entscheidung 1)."
            }
            if type == .staticText, state.toolbarFrames.contains(where: { $0.contains(frame) }) {
                return "Fenstertitel in der Symbolleiste im Systemstil (A11, Entscheidung 1)."
            }
            if type == .staticText, state.titlebarFrames.contains(where: { $0.contains(frame) }) {
                return "Fenstertitel in der Titelleiste der Einstellungen im Systemstil (A11, Entscheidung 1)."
            }
            if identifier.hasSuffix(".emptyState.title") || identifier == "detail.notFound.title" {
                return "Label aus grauem Symbol und Titel, der Audit misst beides zusammen; der Titel selbst hat 12:1 (EmptyStateSnapshotTests)."
            }
            if ["quickOpen.hint", "quickOpen.emptyState.message", "slash.hint"].contains(identifier) {
                return "secondary auf Glas im Systemstil (A11, Entscheidung zu A11)."
            }
            if ["trash.row", "trash.header.title", "trash.header.subtitle"].contains(identifier),
               let sheet = state.sheetElementFrames, !sheet.contains(frame) {
                return "Zeile oder Kopf des Papierkorbs hinter dem Sheet „Backup wiederherstellen“, das System zeichnet sie gedimmt."
            }
            if identifier == "detail.emptyState.message", let sheet = state.sheetElementFrames, !sheet.contains(frame) {
                return "Leerzustand hinter dem Sheet „Sync nach dem Backup“, das System zeichnet ihn gedimmt; ohne Sheet prüft ihn „Fenster ohne Seite“."
            }
            if identifier == "sidebar.emptyState.message" {
                return "primary auf dem Glas der Sidebar; der Kontrast hängt vom Hintergrund hinter dem Fenster ab. Auf festem Hintergrund prüft EmptyStateSnapshotTests 4,5:1 (A15, Entscheidung zum Sidebar-Glas)."
            }
            if identifier == "timeTravel.day", type == .staticText {
                return "Tag (primary) auf dem Glas der Seitenleiste der Zeitreise; der Kontrast hängt vom Hintergrund hinter dem Fenster ab, im dunklen Erscheinungsbild rot, auch vor Phase 15 (Review von Phase 15, wie beim Sidebar-Glas)."
            }
            if identifier == "reminder.marker.date",!state.layoutGroupFrames.contains(where: { $0.contains(frame) }) {
                return "Überschrift (primary) im Popover am rechten Rand, der über das Fenster hinausragt; das Glas zeigt, was hinter dem Fenster liegt (Entscheidung 15.4, wie beim Sidebar-Glas)."
            }
        default:
            break
        }
        return nil
    }

    private static func layout(of snapshot: any XCUIElementSnapshot) -> [String] {
        ["\(snapshot.elementType.rawValue) \(snapshot.identifier) \(snapshot.label) \(snapshot.frame)"]
            + snapshot.children.flatMap { layout(of: $0) }
    }

    private static func describe(_ issue: XCUIAccessibilityAuditIssue) -> String {
        let element = issue.element.map { element in
            "\(element.elementType.rawValue) id=\(element.identifier) label=\(element.label) value=\(element.value ?? "") frame=\(element.frame)"
        } ?? "ohne Element"
        return "\(issue.compactDescription) [\(issue.auditType.rawValue)] \(element) – \(issue.detailedDescription)"
    }

    // MARK: - Hilfen

    /// ⌘N, dann Titel tippen (der Fokus liegt danach im Titelfeld).
    private func createPage(_ name: String) {
        let outline = window.outlines["sidebar.pages"]
        let count = outline.pageRows.count
        app.typeKey("n", modifierFlags: .command)
        let added = NSPredicate { _, _ in outline.pageRows.count == count + 1 }
        wait(for: [expectation(for: added, evaluatedWith: nil)], timeout: 5)
        let title = window.descendants(matching: .any)["detail.title"]
        let focused = NSPredicate { _, _ in title.value(forKey: "hasKeyboardFocus") as? Bool == true }
        wait(for: [expectation(for: focused, evaluatedWith: nil)], timeout: 5)
        app.typeText(name)
    }
}
