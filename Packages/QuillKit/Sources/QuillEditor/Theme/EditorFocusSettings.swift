#if canImport(AppKit)
import AppKit
import Observation

/// Fokus-Modus (Phase 18.1): Schreibmaschinen-Scrollen und abgedunkelte Umgebung.
/// Pro Mac in den Einstellungen (`UserDefaults`), nicht im Store, in Backups oder im
/// Export, wie das Theme (ADR-024).
///
/// Ein Wechsel wirkt sofort in allen Fenstern: Die Editoren beobachten `didChange`.
/// Er ändert keinen Text, ist also kein Undo-Schritt und löst kein Speichern aus.
@MainActor
@Observable
public final class EditorFocusSettings {
    public static let shared = EditorFocusSettings()
    public static let didChange = Notification.Name("io.github.vogelwild07.quill.editorFocusDidChange")
    /// Schlüssel in `UserDefaults`.
    public static let defaultsKey = "QuillFocusMode"

    public private(set) var isEnabled = false
    /// Ohne `UserDefaults` (UI-Tests, Unit-Tests) gilt die Wahl nur bis zum Beenden.
    @ObservationIgnored private var defaults: UserDefaults?

    init() {}

    /// Liest die gespeicherte Wahl und speichert künftige Wechsel in `defaults`.
    public func configure(defaults: UserDefaults?, initial: Bool? = nil) {
        self.defaults = defaults
        apply(initial ?? defaults?.bool(forKey: Self.defaultsKey) ?? false)
    }

    public func setEnabled(_ isEnabled: Bool) {
        guard isEnabled != self.isEnabled else { return }
        defaults?.set(isEnabled, forKey: Self.defaultsKey)
        apply(isEnabled)
    }

    public func toggle() { setEnabled(!isEnabled) }

    private func apply(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
#endif
