#if canImport(AppKit) && DEBUG
import AppKit
import OSLog

/// Startargument `-QuillWindowsOnMainScreen YES`: Jedes Fenster liegt auf dem
/// Hauptbildschirm (der mit der Menüleiste). Für UI-Tests (`XCUIApplication.quill()`),
/// damit Messungen wie der Kontrast-Audit mit mehreren Monitoren gleich ausfallen.
/// Nur im Debug-Build, nur aus der Kommandozeile.
@MainActor
public enum TestWindowScreen {
    static let argument = "QuillWindowsOnMainScreen"

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "window")
    private static var observations: [NSObjectProtocol] = []

    static func isRequested(arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(of: "-\(argument)"), arguments.indices.contains(index + 1) else { return false }
        return ["YES", "1", "true"].contains(arguments[index + 1])
    }

    /// Neuer Rahmen auf `main` (sichtbarer Bereich), mittig, höchstens so groß wie
    /// dieser; `nil`, wenn das Fenster schon ganz darauf liegt.
    static func frame(_ frame: NSRect, on main: NSRect) -> NSRect? {
        guard !main.contains(frame) else { return nil }
        let size = NSSize(width: min(frame.width, main.width), height: min(frame.height, main.height))
        return NSRect(x: main.midX - size.width / 2, y: main.midY - size.height / 2, width: size.width, height: size.height).integral
    }

    /// Legt alle sichtbaren Fenster auf den Hauptbildschirm und jedes, das später
    /// aktiv wird oder den Bildschirm wechselt.
    public static func start(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard isRequested(arguments: arguments), observations.isEmpty else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didChangeScreenNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated { if let window { place(window) } }
            })
        }
        for window in NSApp.windows where window.isVisible { place(window) }
        logger.notice("Fenster für UI-Tests auf dem Hauptbildschirm (\(argument, privacy: .public))")
    }

    private static func place(_ window: NSWindow) {
        guard window.sheetParent == nil, window.parent == nil, let main = NSScreen.screens.first,
              let target = frame(window.frame, on: main.visibleFrame)
        else { return }
        window.setFrame(target, display: true)
    }
}
#endif
