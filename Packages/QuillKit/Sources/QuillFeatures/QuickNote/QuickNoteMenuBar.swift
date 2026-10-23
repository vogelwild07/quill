#if canImport(AppKit)
import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// Symbol in der Menüleiste, Kürzel ⌃⌥⌘N und schwebendes Fenster der Schnellnotiz
/// (15.3, ADR-033). Folgt den Schaltern in `QuickNote`; ausgeschaltet bleibt nichts übrig.
@MainActor
public final class QuickNoteMenuBar: NSObject {
    private let note: QuickNote
    private var statusItem: NSStatusItem?
    private var hotKey: GlobalHotKey?
    private var panel: NSPanel?

    public init(note: QuickNote) {
        self.note = note
        super.init()
        follow()
    }

    /// Wendet die Schalter an und folgt ihren Änderungen.
    private func follow() {
        withObservationTracking {
            apply(enabled: note.isEnabled, shortcut: note.wantsShortcut)
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
    }

    private func apply(enabled: Bool, shortcut: Bool) {
        if enabled, statusItem == nil {
            statusItem = makeStatusItem()
        } else if !enabled, let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            panel?.orderOut(nil)
        }
        if shortcut, hotKey == nil {
            hotKey = GlobalHotKey(keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey | cmdKey) { [weak self] in self?.show() }
            note.reportShortcut(taken: hotKey == nil)
        } else if !shortcut {
            hotKey?.unregister()
            hotKey = nil
            note.reportShortcut(taken: false)
        }
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let label = String(localized: "Schnellnotiz", bundle: .module)
            button.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: label)
            button.toolTip = label
            button.target = self
            button.action = #selector(toggle)
            button.setAccessibilityIdentifier("quicknote.statusItem")
        }
        return item
    }

    @objc private func toggle() {
        if panel?.isVisible == true {
            panel?.orderOut(nil)
        } else {
            show()
        }
    }

    /// Zeigt das Fenster, ohne Quill nach vorn zu holen.
    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        // Neu je Aufruf, damit das Textfeld den Fokus bekommt; der Entwurf liegt in `note`.
        panel.contentView = NSHostingView(rootView: QuickNoteView(note: note) { [weak panel] in panel?.orderOut(nil) })
        if !panel.isVisible { panel.center() }
        panel.makeKeyAndOrderFront(nil)
        // Fokus ins Textfeld; `defaultFocus` greift in einem Fenster ohne Aktivierung nicht.
        panel.layoutIfNeeded()
        if let textView = Self.firstTextView(in: panel.contentView) { panel.makeFirstResponder(textView) }
    }

    private static func firstTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView { return textView }
        return view.subviews.lazy.compactMap { firstTextView(in: $0) }.first
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = String(localized: "Schnellnotiz", bundle: .module)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setAccessibilityIdentifier("quicknote.panel")
        return panel
    }
}
#endif
