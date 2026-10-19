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
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("de.vogel.quill.uitests.\(UUID().uuidString)"))

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication.quill(storeDirectory: storeDirectory)
        app.launchArguments += ["-QuillPasteboardName", pasteboard.name.rawValue]
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
        audit("Leere Seite (Titel fokussiert)")
        app.typeText("\r")
        audit("Leere Seite (Editor fokussiert)")

        createPage("Inhalt")
        app.typeText("\r")
        app.typeText("# Überschrift\rText mit Inhalt\r[] Aufgabe\r\r> Zitat\r\r")
        pasteboard.clearContents()
        pasteboard.setData(Self.png(width: 120, height: 60), forType: .png)
        app.typeKey("v", modifierFlags: .command)
        window.buttons["page.favorite"].click()
        audit("Seite mit Inhalt, Favorit")

        app.typeText("/")
        audit("Slash-Menü")
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("o", modifierFlags: .command)
        audit("Schnell öffnen (leer)")
        app.typeText("Inh")
        audit("Schnell öffnen (Treffer)")
        app.typeText("xyzq")
        audit("Schnell öffnen (keine Treffer)")
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

    // MARK: - Audit

    private var window: XCUIElement { app.windows.firstMatch }

    /// Was die Ausnahmen über die Ansicht wissen müssen; einmal vor dem Audit erhoben.
    private struct ViewState {
        /// Hüllen von SwiftUI: Fenster, Spalten des `NavigationSplitView`, Sheet.
        var layoutGroupFrames: [CGRect]
        /// Hosting-View im Seitenkopf (unter der beschrifteten Gruppe „Seitenkopf“).
        var headerContentFrame: CGRect?
        var toolbarFrame: CGRect?
        /// „Emojis & Symbole“ in der Touch Bar.
        var touchBarEmojiFrame: CGRect?
        /// Elemente im Sheet; alle anderen liegen dahinter.
        var sheetElementFrames: [CGRect]?
        var isTextFieldFocused: Bool
    }

    private func viewState() -> ViewState {
        func frames(_ query: XCUIElementQuery) -> [CGRect] { query.allElementsBoundByIndex.map(\.frame) }
        let sheet = window.sheets.firstMatch
        let header = window.textViews["editor.text"].groups["Seitenkopf"].children(matching: .group).firstMatch
        let toolbar = window.toolbars.firstMatch
        let emoji = app.touchBars.firstMatch.popUpButtons["Emojis & Symbole"]
        return ViewState(
            layoutGroupFrames: frames(window.children(matching: .group))
                + frames(window.splitGroups.firstMatch.children(matching: .group))
                + (sheet.exists ? frames(sheet.children(matching: .group)) : []),
            headerContentFrame: header.exists ? header.frame : nil,
            toolbarFrame: toolbar.exists ? toolbar.frame : nil,
            touchBarEmojiFrame: emoji.exists ? emoji.frame : nil,
            sheetElementFrames: sheet.exists ? [sheet.frame] + frames(sheet.descendants(matching: .any)) : nil,
            isTextFieldFocused: app.textFields.matching(NSPredicate(format: "hasKeyboardFocus == true")).count > 0
        )
    }

    private func audit(_ view: String) {
        Thread.sleep(forTimeInterval: 0.5)
        let state = viewState()
        var unexpected: [String] = []
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                if self.exception(for: issue, in: state) == nil {
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
        case .parentChild:
            if element == nil, state.isTextFieldFocused {
                return "Feld-Editor von AppKit eines fokussierten Textfelds; tritt bei jedem SwiftUI-Textfeld auf (A6)."
            }
        case .contrast:
            if identifier == "sidebar.group" {
                return "Gruppenköpfe im Systemstil der Source-List (A10, Entscheidung 1)."
            }
            if type == .staticText, state.toolbarFrame?.contains(frame) == true {
                return "Fenstertitel in der Symbolleiste im Systemstil (A11, Entscheidung 1)."
            }
            if identifier.hasSuffix(".emptyState.title") || identifier == "detail.notFound.title" {
                return "Label aus grauem Symbol und Titel, der Audit misst beides zusammen; der Titel selbst hat 12:1 (EmptyStateSnapshotTests)."
            }
            if ["quickOpen.hint", "quickOpen.emptyState.message", "slash.hint"].contains(identifier) {
                return "secondary auf Glas im Systemstil (A11, Entscheidung zu A11)."
            }
            if let sheet = state.sheetElementFrames, !sheet.contains(frame) {
                return "Inhalt hinter einem Sheet zeichnet das System gedimmt."
            }
        default:
            break
        }
        return nil
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

    private static func png(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
        return rep.representation(using: .png, properties: [:])!
    }
}
