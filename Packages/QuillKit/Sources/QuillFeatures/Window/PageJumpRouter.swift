#if canImport(AppKit)
import AppKit
import Observation

/// Sprung zu einer Seite aus einem anderen Fenster, z. B. aus Einstellungen › Sync
/// zu einem Konflikt (11.6). Das vorderste Quill-Fenster nimmt den Sprung an; gibt es
/// keines, öffnet sich eines mit der Seite (`WindowRouter`).
@MainActor
@Observable
final class PageJumpRouter {
    static let shared = PageJumpRouter()

    struct Request: Equatable {
        let id = UUID()
        let pageID: UUID
        let blockID: UUID?
        let window: ObjectIdentifier
    }

    private(set) var request: Request?
    @ObservationIgnored private var windows: [ObjectIdentifier: () -> NSWindow?] = [:]

    /// Jedes Hauptfenster meldet sich beim Erscheinen an.
    func register(_ window: NSWindow) {
        windows[ObjectIdentifier(window)] = { [weak window] in window }
    }

    /// `false`, wenn kein Hauptfenster offen ist; dann öffnet der Aufrufer eines.
    func jump(to pageID: UUID, blockID: UUID?) -> Bool {
        windows = windows.filter { $0.value() != nil }
        guard let window = NSApp.orderedWindows.first(where: { windows[ObjectIdentifier($0)] != nil }) else { return false }
        request = Request(pageID: pageID, blockID: blockID, window: ObjectIdentifier(window))
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// Das Fenster nimmt den Sprung an, wenn er ihm gilt.
    func claim(for window: NSWindow?) -> Request? {
        guard let window, let request, request.window == ObjectIdentifier(window) else { return nil }
        self.request = nil
        return request
    }
}
#endif
