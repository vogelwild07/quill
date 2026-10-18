#if canImport(AppKit)
import AppKit
import SwiftUI

/// Übergibt einem neu geöffneten Fenster seine Startseite und hängt es bei Bedarf
/// als Tab an ein bestehendes Fenster (ADR-004).
///
/// Ablauf: `prepare(…)`, dann `openWindow(id: WindowRouter.windowID)`. Das neue
/// Fenster ruft beim Erscheinen `claim(for:)` auf.
@MainActor
final class WindowRouter {
    static let shared = WindowRouter()
    static let windowID = "main"

    private struct Request {
        let pageID: UUID?
        weak var tabOf: NSWindow?
        let date: Date
    }

    private var pending: Request?

    func prepare(pageID: UUID?, asTabOf window: NSWindow?) {
        pending = Request(pageID: pageID, tabOf: window, date: .now)
    }

    /// Nimmt eine offene Anfrage an (höchstens 2 s alt, damit eine liegen
    /// gebliebene nie ein späteres Fenster erwischt) und liefert die Startseite.
    func claim(for window: NSWindow) -> UUID? {
        guard let request = pending, Date.now.timeIntervalSince(request.date) < 2 else {
            pending = nil
            return nil
        }
        pending = nil
        if let host = request.tabOf, host !== window {
            host.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        }
        return request.pageID
    }
}

/// Meldet das `NSWindow`, sobald die View in einem Fenster hängt (einmalig).
struct WindowAccessor: NSViewRepresentable {
    var onAttach: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> AttachView {
        let view = AttachView()
        view.onAttach = onAttach
        return view
    }

    func updateNSView(_ nsView: AttachView, context: Context) {}

    final class AttachView: NSView {
        var onAttach: (@MainActor (NSWindow) -> Void)?
        private var didAttach = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !didAttach else { return }
            didAttach = true
            // Erst nach dem Einblenden, sonst greift addTabbedWindow nicht zuverlässig.
            DispatchQueue.main.async { [onAttach] in onAttach?(window) }
        }
    }
}
#endif
