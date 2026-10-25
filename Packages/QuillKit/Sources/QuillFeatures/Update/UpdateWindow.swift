#if canImport(AppKit)
import AppKit
import QuillUpdate
import SwiftUI

/// Fenster „Update“ (ADR-037). Schließen gilt als „Später“ bzw. „Abbrechen“.
@MainActor
final class UpdateWindow: NSObject, NSWindowDelegate {
    private let model: UpdateModel
    private let window: NSWindow

    init(model: UpdateModel) {
        self.model = model
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        super.init()
        window.title = String(localized: "Update", bundle: .module)
        window.contentView = NSHostingView(rootView: UpdateView(model: model))
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.setAccessibilityIdentifier("update.window")
        window.delegate = self
    }

    func show() {
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if model.isPresented { model.close() }
    }
}
#endif
