#if canImport(AppKit)
import AppKit
import Observation
import QuillEditorCore
import SwiftUI

@MainActor
@Observable
final class SlashMenuModel {
    var commands: [SlashCommand] = SlashCommand.all
    var selection = 0
    var onChoose: (SlashCommand) -> Void = { _ in }
}

/// Steuert das Slash-Menü: Öffnen nach „/“, Filtern beim Tippen, Tastatur, Auswahl.
@MainActor
final class SlashMenuController {
    private unowned let editor: BlockEditorController
    private let model = SlashMenuModel()
    private var panel: NSPanel?
    /// Position des „/“ im Textspeicher.
    private var slashLocation: Int?

    init(editor: BlockEditorController) {
        self.editor = editor
        model.onChoose = { [weak self] command in self?.choose(command) }
    }

    var isVisible: Bool { slashLocation != nil }

    /// Aktuelle Treffer (für Tests).
    var commands: [SlashCommand] { model.commands }

    /// Öffnet das Menü, wenn „/“ am Blockanfang oder nach Leerraum steht (nicht im Code).
    func openIfAllowed(slashLocation location: Int) {
        let block = editor.blockIndex(atCharacter: location)
        guard editor.document[block].kind != .code else { return }
        if location > 0 {
            let previous = editor.text(in: NSRange(location: location - 1, length: 1))
            guard previous.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
                || editor.position(atCharacter: location).offset == 0 else { return }
        }
        slashLocation = location
        model.commands = SlashCommand.all
        model.selection = 0
        show()
    }

    /// Nach jeder Änderung: Filter aktualisieren oder schließen.
    func update() {
        guard let slashLocation else { return }
        let caret = editor.caretLocation
        guard caret > slashLocation,
              editor.text(in: NSRange(location: slashLocation, length: 1)) == "/",
              editor.blockIndex(atCharacter: caret) == editor.blockIndex(atCharacter: slashLocation) else {
            close()
            return
        }
        let query = editor.text(in: NSRange(location: slashLocation + 1, length: caret - slashLocation - 1))
        if query.hasPrefix(" ") || query.contains("  ") {
            close()
            return
        }
        let matches = SlashCommand.matching(query)
        if matches.isEmpty && query.count > 3 {
            // Ohne Treffer zu; Escape kann einen Klick auf ＋ danach noch zurücknehmen.
            close(keepingInsert: true)
            return
        }
        model.commands = matches
        model.selection = min(model.selection, max(0, matches.count - 1))
        resizePanel()
    }

    /// Tastatur, solange das Menü offen ist. `true` = verbraucht.
    func handle(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            guard !model.commands.isEmpty else { return true }
            model.selection = (model.selection + 1) % model.commands.count
            announceSelection()
            return true
        case #selector(NSResponder.moveUp(_:)):
            guard !model.commands.isEmpty else { return true }
            model.selection = (model.selection - 1 + model.commands.count) % model.commands.count
            announceSelection()
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            guard model.commands.indices.contains(model.selection) else {
                close()
                return false
            }
            choose(model.commands[model.selection])
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close(keepingInsert: true)
            editor.revertInsertBlockWithMenu()
            return true
        default:
            return false
        }
    }

    /// Index der gewählten Zeile (für Tests).
    var selection: Int { model.selection }

    /// VoiceOver bleibt im Text; die gewählte Zeile wird angesagt.
    private func announceSelection() {
        guard model.commands.indices.contains(model.selection) else { return }
        NSAccessibility.post(element: editor.textView, notification: .announcementRequested, userInfo: [
            .announcement: model.commands[model.selection].title,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    func choose(_ command: SlashCommand) {
        guard let slashLocation else { return }
        let caret = max(editor.caretLocation, slashLocation + 1)
        close()
        editor.deleteText(in: NSRange(location: slashLocation, length: caret - slashLocation))
        if command.kind == .image {
            editor.chooseImages(at: slashLocation)
        } else {
            editor.setKind(command.kind, ofBlockAtCharacter: slashLocation)
        }
    }

    /// `keepingInsert`: ein Klick auf ＋ bleibt für Escape zurücknehmbar.
    func close(keepingInsert: Bool = false) {
        slashLocation = nil
        if !keepingInsert { editor.pendingInsert = nil }
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    // MARK: Panel

    private func show() {
        guard let window = editor.window, let slashLocation else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        resizePanel()
        let caret = editor.screenRect(forCharacter: slashLocation)
        var origin = CGPoint(x: caret.minX - 8, y: caret.minY - panel.frame.height - 6)
        if let screen = window.screen, origin.y < screen.visibleFrame.minY {
            origin.y = caret.maxY + 6
        }
        panel.setFrameOrigin(origin)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    private func resizePanel() {
        guard let panel else { return }
        let rows = CGFloat(max(1, model.commands.count)) * 34
        let headers = CGFloat(Set(model.commands.map(\.group)).count) * 24
        let height = min(rows + headers + 58, 400)
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size = CGSize(width: 280, height: height)
        panel.setFrame(frame, display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 280, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        let content = NSHostingView(rootView: SlashMenuView(model: model))
        // VoiceOver: Panel und Hosting-View (bleibt trotz `setAccessibilityElement(false)`
        // eine Gruppe) tragen den Namen des Menüs.
        let label = String(localized: "Block einfügen", bundle: .module)
        panel.setAccessibilityLabel(label)
        content.setAccessibilityLabel(label)
        panel.contentView = content
        return panel
    }
}

struct SlashMenuView: View {
    @Bindable var model: SlashMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.commands.isEmpty {
                Text("Keine Treffer", bundle: .module)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        // `commands` ist nach Abschnitten geordnet; Indizes bleiben die der Liste.
                        ForEach(SlashCommand.Group.allCases, id: \.self) { group in
                            let items = Array(model.commands.enumerated()).filter { $0.element.group == group }
                            if !items.isEmpty {
                                Text(group.title.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .frame(height: 22, alignment: .bottom)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(items, id: \.element.id) { index, command in
                                    row(command, index: index)
                                        .id(index)
                                }
                            }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selection) { _, selection in proxy.scrollTo(selection) }
            }
            Divider()
            Text("↑↓ wählen   ↩ einfügen   ⎋ schließen", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityIdentifier("slash.hint")
        }
        .frame(width: 280)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("slash.menu")
    }

    private static let selectedText = Color(nsColor: .alternateSelectedControlTextColor)

    private func row(_ command: SlashCommand, index: Int) -> some View {
        let isSelected = index == model.selection
        return HStack(spacing: 10) {
            Image(systemName: command.symbol)
                .frame(width: 22)
                .foregroundStyle(isSelected ? Self.selectedText : Color.secondary)
            Text(command.title)
            Spacer()
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isSelected ? Self.selectedText.opacity(0.8) : Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .foregroundStyle(isSelected ? Self.selectedText : Color.primary)
        .background(isSelected ? Color.accentColor : Color.clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onTapGesture { model.onChoose(command) }
        // Nur echte Mausbewegung wählt aus, nicht das Scrollen per Tastatur.
        .onContinuousHover { phase in
            if case .active = phase, model.selection != index { model.selection = index }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(command.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("slash.\(command.kind.rawValue)")
        .accessibilityAction { model.onChoose(command) }
    }
}
#endif
