#if canImport(AppKit) && DEBUG
import AppKit
import OSLog

/// Startargument `-QuillWindowSize <Breite>x<Höhe>`: Das erste Fenster bekommt diese
/// Größe in Punkten, für die Bilder in der README (`ReadmeScreenshotUITests`).
/// XCUITest vergrößert Fenster nicht zuverlässig per Ziehen. Nur im Debug-Build,
/// nur aus der Kommandozeile.
@MainActor
public enum TestWindowSize {
    static let argument = "QuillWindowSize"

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "window")

    /// Größe aus den Startargumenten, je Seite 400…4000 Punkte.
    static func size(arguments: [String]) -> CGSize? {
        guard let index = arguments.firstIndex(of: "-\(argument)"), arguments.indices.contains(index + 1) else { return nil }
        let parts = arguments[index + 1].split(separator: "x", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 2, let width = parts[0], let height = parts[1],
              (400...4000).contains(width), (400...4000).contains(height) else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Wartet bis zu 5 s auf das erste Fenster und setzt dessen Größe; die linke
    /// obere Ecke bleibt.
    public static func applyToFirstWindow(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let size = size(arguments: arguments) else { return }
        Task {
            for _ in 0..<50 {
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                    var frame = window.frame
                    frame.origin.y += frame.height - size.height
                    frame.size = size
                    window.setFrame(window.constrainFrameRect(frame, to: window.screen), display: true)
                    logger.notice("Fenstergröße für UI-Tests gesetzt (\(argument, privacy: .public))")
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            logger.error("Kein Fenster für \(argument, privacy: .public)")
        }
    }
}
#endif
