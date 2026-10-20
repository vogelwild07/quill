import Foundation
import Observation
import QuillEditorCore

/// Gewähltes Theme, pro Gerät in den Einstellungen (`UserDefaults`), nicht im Store,
/// in Backups oder im Export (ADR-024).
///
/// Ein Wechsel wirkt sofort in allen Fenstern: Die Editoren beobachten `didChange`
/// und zeichnen neu. Er ändert keinen Text, ist also kein Undo-Schritt und löst
/// kein Speichern aus.
@MainActor
@Observable
public final class EditorThemeSettings {
    public static let shared = EditorThemeSettings()
    public static let didChange = Notification.Name("io.github.vogelwild07.quill.editorThemeDidChange")
    /// Schlüssel in `UserDefaults`.
    public static let defaultsKey = "QuillEditorTheme"

    public private(set) var selection: EditorTheme.ID = .standard
    /// „Kontrast erhöhen“ in den Bedienungshilfen.
    public private(set) var increaseContrast = false
    /// Ohne `UserDefaults` (UI-Tests, Unit-Tests) gilt die Wahl nur bis zum Beenden.
    @ObservationIgnored private var defaults: UserDefaults?
    @ObservationIgnored private var contrastObservation: NotificationObservation?

    public var theme: EditorTheme { EditorTheme.with(id: selection) }

    init() {
        increaseContrast = Platform.increasesContrast
        EditorThemeState.setIncreaseContrast(increaseContrast)
        let change = Platform.increasesContrastDidChange
        contrastObservation = NotificationObservation(change.name, object: nil, center: change.center) { _ in
            MainActor.assumeIsolated {
                EditorThemeSettings.shared.setIncreaseContrast(Platform.increasesContrast)
            }
        }
    }

    /// „Kontrast erhöhen“ geändert: Farben neu ableiten und alle Editoren neu zeichnen.
    func setIncreaseContrast(_ increaseContrast: Bool) {
        self.increaseContrast = increaseContrast
        EditorThemeState.setIncreaseContrast(increaseContrast)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Liest die gespeicherte Wahl und speichert künftige Wechsel in `defaults`.
    /// Unbekannte Werte (z. B. aus einer neueren Version) ergeben „Standard“.
    public func configure(defaults: UserDefaults?, initial: EditorTheme.ID? = nil) {
        self.defaults = defaults
        let stored = defaults?.string(forKey: Self.defaultsKey).flatMap(EditorTheme.ID.init(rawValue:))
        apply(initial ?? stored ?? .standard)
    }

    public func select(_ id: EditorTheme.ID) {
        guard id != selection else { return }
        defaults?.set(id.rawValue, forKey: Self.defaultsKey)
        apply(id)
    }

    private func apply(_ id: EditorTheme.ID) {
        selection = id
        EditorThemeState.setTheme(EditorTheme.with(id: id))
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
