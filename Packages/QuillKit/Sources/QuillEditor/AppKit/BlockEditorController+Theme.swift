#if canImport(AppKit)
import AppKit

/// Theme des Editors (ADR-024). Die Farben im Textspeicher sind dynamisch und lösen
/// sich beim Zeichnen auf; ein Wechsel zeichnet nur neu und ändert keinen Text, ist
/// also kein Undo-Schritt und kein Speichern.
extension BlockEditorController {
    func observeTheme() {
        let apply: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTheme() }
        }
        // Auch „Kontrast erhöhen“ kommt über `didChange` (`EditorThemeSettings`).
        themeObservations = [NotificationObservation(EditorThemeSettings.didChange, object: nil, using: apply)]
        applyTheme()
    }

    /// Feste Themes erzwingen hell oder dunkel nur im Editor; Sidebar und Symbolleiste
    /// bleiben beim System.
    func applyTheme() {
        let appearance = EditorThemeState.theme.forcedAppearance
        if scrollView.appearance?.name != appearance?.name {
            scrollView.appearance = appearance
        }
        // Gleiche Darstellung, andere Farben: Fragmente zeichnen sonst aus dem Zwischenspeicher.
        if let layoutManager = textView.textLayoutManager {
            layoutManager.invalidateLayout(for: layoutManager.documentRange)
        }
        textView.updateLayerColors()
        textView.needsLayout = true
        textView.needsDisplay = true
        for subview in textView.subviews { subview.needsDisplay = true }
    }
}
#endif
