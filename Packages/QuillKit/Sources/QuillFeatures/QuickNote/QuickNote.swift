import Foundation
import Observation
import QuillModel

/// Schnellnotiz (15.3, ADR-033): Wahl pro Mac in `UserDefaults`, Standard aus, und der
/// Entwurf, der bis zum Sichern nur im Speicher bleibt.
@MainActor
@Observable
public final class QuickNote {
    /// Schlüssel in `UserDefaults`.
    public static let enabledKey = "QuillQuickNoteEnabled"
    public static let shortcutKey = "QuillQuickNoteShortcut"

    public enum Failure: Error, Equatable {
        /// Nichts außer Leerzeichen.
        case empty
    }

    /// Symbol in der Menüleiste.
    public private(set) var isEnabled: Bool
    /// Kürzel in allen Apps; wirkt nur mit dem Symbol.
    public private(set) var isShortcutEnabled: Bool
    /// Das Kürzel konnte nicht angemeldet werden, meist weil eine andere App es hat.
    public private(set) var isShortcutTaken = false
    public var draft = ""
    public private(set) var isSaving = false
    @ObservationIgnored private let store: PageStore
    @ObservationIgnored private let defaults: UserDefaults?

    /// Ohne `defaults` gilt die Wahl nur bis zum Beenden.
    init(store: PageStore, defaults: UserDefaults?) {
        self.store = store
        self.defaults = defaults
        isEnabled = defaults?.bool(forKey: Self.enabledKey) ?? false
        isShortcutEnabled = defaults?.bool(forKey: Self.shortcutKey) ?? false
    }

    /// Kürzel gewünscht und möglich.
    public var wantsShortcut: Bool { isEnabled && isShortcutEnabled }

    public var canSave: Bool {
        !isSaving && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults?.set(enabled, forKey: Self.enabledKey)
    }

    public func setShortcutEnabled(_ enabled: Bool) {
        isShortcutEnabled = enabled
        defaults?.set(enabled, forKey: Self.shortcutKey)
    }

    func reportShortcut(taken: Bool) {
        if taken != isShortcutTaken { isShortcutTaken = taken }
    }

    /// Neue Seite aus dem Entwurf: erste Zeile mit Text als Titel, jede weitere Zeile ein
    /// Absatz. Danach ist der Entwurf leer, außer er hat sich währenddessen geändert.
    @discardableResult
    public func save() async throws -> UUID {
        let saved = draft
        let lines = saved.components(separatedBy: .newlines)
        guard !isSaving, let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw Failure.empty
        }
        isSaving = true
        defer { isSaving = false }
        let page = try await PageIntentActions(store: store).createPage(
            title: lines[first], text: lines[(first + 1)...].joined(separator: "\n")
        )
        if draft == saved { draft = "" }
        return page.id
    }
}
