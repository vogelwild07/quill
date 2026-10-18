#if canImport(AppKit)
import QuillEditor
import SwiftUI

/// Menüleiste von Quill. Kürzel wie in Apple Notizen: ⌘N Neue Seite,
/// ⇧⌘N Neue Unterseite, ⌥⌘N Neues Fenster, ⌘T Neuer Tab.
public struct QuillCommands: Commands {
    let persistence: QuillPersistence?

    @FocusedValue(\.pageActions) private var actions
    @Environment(\.openWindow) private var openWindow

    public init(persistence: QuillPersistence?) {
        self.persistence = persistence
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "Neue Seite", bundle: .module)) {
                if let actions {
                    actions.newPage()
                } else {
                    openWindow(id: WindowRouter.windowID)
                }
            }
            .keyboardShortcut("n")

            Button(String(localized: "Neue Unterseite", bundle: .module)) {
                actions?.newSubpage()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(actions?.selection == nil)

            Divider()

            Button(String(localized: "Neuer Tab", bundle: .module)) {
                WindowRouter.shared.prepare(pageID: nil, asTabOf: NSApp.keyWindow)
                openWindow(id: WindowRouter.windowID)
            }
            .keyboardShortcut("t")

            Button(String(localized: "Neues Fenster", bundle: .module)) {
                openWindow(id: WindowRouter.windowID)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }

        CommandGroup(after: .importExport) {
            Divider()
            Button(String(localized: "Backups im Finder zeigen", bundle: .module)) {
                persistence?.revealBackups()
            }
            .disabled(persistence == nil || persistence?.isInMemory == true)
        }

        // Menü „Format“. Die Aktionen laufen über die Responder-Kette; ohne
        // Block-Editor als Ersthelfer passiert nichts. ⌘E bleibt „Auswahl für Suche
        // verwenden“, deshalb Inline-Code auf ⇧⌘M (siehe architecture.md).
        CommandGroup(after: .textFormatting) {
            formatButton("Fett", #selector(EditorFormattingActions.quillToggleBold(_:)))
                .keyboardShortcut("b")
            formatButton("Kursiv", #selector(EditorFormattingActions.quillToggleItalic(_:)))
                .keyboardShortcut("i")
            formatButton("Code", #selector(EditorFormattingActions.quillToggleInlineCode(_:)))
                .keyboardShortcut("m", modifiers: [.command, .shift])
            formatButton("Durchgestrichen", #selector(EditorFormattingActions.quillToggleStrikethrough(_:)))
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Divider()
            formatButton("Link …", #selector(EditorFormattingActions.quillEditLink(_:)))
                .keyboardShortcut("k")
        }

        CommandMenu(String(localized: "Seite", bundle: .module)) {
            Button(String(localized: "Umbenennen", bundle: .module)) { actions?.rename() }
                .disabled(actions?.selection == nil)
            Divider()
            Button(String(localized: "In neuem Tab öffnen", bundle: .module)) { actions?.openInTab() }
                .disabled(actions?.selection == nil)
            Button(String(localized: "In neuem Fenster öffnen", bundle: .module)) { actions?.openInWindow() }
                .disabled(actions?.selection == nil)
            Divider()
            // Ohne Kürzel: ⌘⌫ löscht in Textfeldern bis zum Zeilenanfang. In der
            // Sidebar legt ⌘⌫ die Seite in den Papierkorb (PageOutlineView).
            Button(String(localized: "In den Papierkorb legen", bundle: .module)) { actions?.trash() }
                .disabled(actions?.selection == nil)
        }
    }

    private func formatButton(_ title: String.LocalizationValue, _ action: Selector) -> some View {
        Button(String(localized: title, bundle: .module)) {
            NSApp.sendAction(action, to: nil, from: nil)
        }
    }
}
#endif
