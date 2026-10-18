#if canImport(AppKit)
import AppKit
import Observation
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
            close()
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
            return true
        case #selector(NSResponder.moveUp(_:)):
            guard !model.commands.isEmpty else { return true }
            model.selection = (model.selection - 1 + model.commands.count) % model.commands.count
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            guard model.commands.indices.contains(model.selection) else {
                close()
                return false
            }
            choose(model.commands[model.selection])
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    func choose(_ command: SlashCommand) {
        guard let slashLocation else { return }
        let caret = max(editor.caretLocation, slashLocation + 1)
        close()
        editor.deleteText(in: NSRange(location: slashLocation, length: caret - slashLocation))
        editor.setKind(command.kind, ofBlockAtCharacter: slashLocation)
    }

    func close() {
        slashLocation = nil
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
        let rows = max(1, min(model.commands.count, 8))
        let height = CGFloat(rows) * 34 + 46
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
        panel.contentView = NSHostingView(rootView: SlashMenuView(model: model))
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
                    VStack(spacing: 2) {
                        ForEach(Array(model.commands.enumerated()), id: \.element.id) { index, command in
                            row(command, isSelected: index == model.selection)
                                .id(index)
                                .onTapGesture { model.onChoose(command) }
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
        }
        .frame(width: 280)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func row(_ command: SlashCommand, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: command.symbol)
                .frame(width: 22)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
            Text(command.title)
            Spacer()
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(isSelected ? Color.accentColor : Color.clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
    }
}
#endif
