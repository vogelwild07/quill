#if canImport(AppKit)
import QuillEditor
import QuillEditorCore
import SwiftUI

/// Menüleiste von Quill. Kürzel wie in Apple Notizen: ⌘N Neue Seite,
/// ⇧⌘N Neue Unterseite, ⌥⌘N Neues Fenster, ⌘T Neuer Tab, ⌘O Schnell öffnen.
public struct QuillCommands: Commands {
    let persistence: QuillPersistence?

    @FocusedValue(\.pageActions) private var actions
    @FocusedValue(\.windowActions) private var windowActions
    @FocusedValue(\.readOnlyEditor) private var readOnlyEditor
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

            Divider()

            Button(String(localized: "Schnell öffnen …", bundle: .module)) {
                actions?.quickOpen()
            }
            .keyboardShortcut("o")
            .disabled(actions == nil)
        }

        // Menü „Darstellung“, unter den Einträgen zur Seitenleiste. ⇧⌘F ist in
        // Textfeldern frei (⌘F Suchen, ⌥⌘F Ersetzen, ⌃⌘F Vollbild).
        CommandGroup(after: .sidebar) {
            Toggle(String(localized: "Fokus-Modus", bundle: .module), isOn: Binding(
                get: { EditorFocusSettings.shared.isEnabled },
                set: { EditorFocusSettings.shared.setEnabled($0) }
            ))
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        CommandGroup(after: .importExport) {
            Divider()
            Button(String(localized: "Backups im Finder zeigen", bundle: .module)) {
                persistence?.revealBackups()
            }
            .disabled(persistence == nil || persistence?.isInMemory == true)
            Button(String(localized: "Backup wiederherstellen …", bundle: .module)) {
                windowActions?.restoreBackup()
            }
            .disabled(windowActions == nil || persistence?.canRestoreBackups != true)
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
            Divider()
            // ⌥⌘0–7 in Slash-Menü-Reihenfolge; ⌥⌘8 gehört dem Zoom der Bedienungshilfen.
            Menu(String(localized: "Blockart", bundle: .module)) {
                ForEach(BlockConversion.commands) { command in
                    let button = Button(command.title) {
                        NSApp.sendAction(#selector(EditorFormattingActions.quillSetBlockKind(_:)), to: nil, from: BlockKindRequest(command.kind))
                    }
                    .disabled(readOnlyEditor == true)
                    if let digit = BlockConversion.shortcutDigit(for: command.kind) {
                        button.keyboardShortcut(KeyEquivalent(digit), modifiers: [.command, .option])
                    } else {
                        button
                    }
                }
            }
            // Deaktiviert, solange „Schnell öffnen“ offen ist: Dann öffnet ⌘↩ dort in
            // einem neuen Tab; ein aktiver Menüpunkt finge die Taste vorher ab.
            formatButton("Abhaken", #selector(EditorFormattingActions.quillToggleChecked(_:)))
                .keyboardShortcut(.return)
                .disabled(actions?.isQuickOpenShown == true)
            Divider()
            // ⌥⌘↑/↓ statt ⌥⇧↑/↓: Das erweitert in Textfeldern die Auswahl absatzweise.
            formatButton("Block nach oben", #selector(EditorFormattingActions.quillMoveBlockUp(_:)))
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            formatButton("Block nach unten", #selector(EditorFormattingActions.quillMoveBlockDown(_:)))
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            formatButton("Block duplizieren", #selector(EditorFormattingActions.quillDuplicateBlock(_:)))
                .keyboardShortcut("d")
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
            // ⌥⌘Y: frei in Textfeldern und im System (ADR-031).
            Button(String(localized: "Zeitreise …", bundle: .module)) {
                if let selection = actions?.selection { openWindow(id: TimeTravelScene.windowID, value: selection) }
            }
            .keyboardShortcut("y", modifiers: [.command, .option])
            .disabled(actions?.selection == nil)
            // Nur mit bereitem Modell und eingeschalteter KI (ADR-032); ohne Kürzel.
            if persistence?.ai.isUsable == true {
                Button(String(localized: "Zusammenfassen …", bundle: .module)) { actions?.summarize() }
                    .disabled(actions?.selection == nil)
                Button(String(localized: "To-dos vorschlagen …", bundle: .module)) { actions?.suggestTodos() }
                    .disabled(actions?.selection == nil)
            }
            Divider()
            // ⇧⌘E wie „Exportieren“ in vielen Mac-Apps; ⌘E bleibt „Auswahl für Suche verwenden“.
            Button(String(localized: "Exportieren …", bundle: .module)) { actions?.exportPage() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(actions?.selection == nil)
            Divider()
            // Ohne Kürzel: ⌃⌘D (Wörterbuch) und ⌃⌘F (Vollbild) sind belegt.
            Button {
                actions?.toggleFavorite()
            } label: {
                if actions?.isFavorite == true {
                    Text("Aus Favoriten entfernen", bundle: .module)
                } else {
                    Text("Zu Favoriten hinzufügen", bundle: .module)
                }
            }
            .disabled(actions?.selection == nil)
            // Ohne Kürzel: ⌘⌫ löscht in Textfeldern bis zum Zeilenanfang. In der
            // Sidebar legt ⌘⌫ die Seite in den Papierkorb (PageOutlineView).
            Button(String(localized: "In den Papierkorb legen", bundle: .module)) { actions?.trash() }
                .disabled(actions?.selection == nil)
        }
    }

    /// Gesperrt im Lesemodus der Zeitreise; dort tun die Aktionen nichts.
    private func formatButton(_ title: String.LocalizationValue, _ action: Selector) -> some View {
        Button(String(localized: title, bundle: .module)) {
            NSApp.sendAction(action, to: nil, from: nil)
        }
        .disabled(readOnlyEditor == true)
    }
}
#endif
